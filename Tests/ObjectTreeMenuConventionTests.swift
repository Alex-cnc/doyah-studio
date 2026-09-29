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
///
/// ## 锚点归位（开发循环第 110 轮，队列 `L-90` ㈡ 第 2 条）
///
/// 第 110 轮把**作用行解析**从 `ObjectTreeView` 搬进了
/// `App/Views/ObjectTreeContextMenu.swift` 的纯函数 `ObjectTreeMenuTarget.resolve`
/// （与菜单内容同一个文件 —— 界面与判据读同一份），本判据原先钉的是视图里那段**内联**写法
/// ⇒ 当场判红两处。按它自己的纪律（「判据锚点变了，请更新这条判据而不是删掉它」）改成钉新住处：
/// **视图必须把解析交给那个纯函数、且纯函数体内必须仍然「悬停优先 → 兜底选中」**。
/// 语义一字未改，判据强度不减：除源码锚点外，`TestsUISnapshot/ObjectTreeContextMenuProbeTests.swift`
/// 另有拿真行数组喂 `resolve` 的行为判据（悬停优先 / 兜底 / 都没有 → nil）。
final class ObjectTreeMenuConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testContextMenuTargetSurvivesRebuildClearingHover() throws {
        let text = try source("App/Views/ObjectTreeView.swift")

        // ① 菜单内容与作用行都走「那份唯一出处」，且目标必须经 `menuTargetObject`（悬停行 + 兜底）
        //    —— 只看悬停盒子的话，重建补的假 mouseExited 会让菜单变空。
        XCTAssertTrue(
            text.contains("ObjectTreeContextMenu.items("),
            "菜单内容必须走 `ObjectTreeContextMenu.items(`（唯一出处）—— 视图里另写一份就会与判据漂移"
        )
        XCTAssertTrue(
            text.contains("object: menuTargetObject"),
            "菜单目标必须走 `menuTargetObject`（悬停行 + 兜底）—— 只看悬停盒子的话，重建补的假 mouseExited 会让菜单变空"
        )
        XCTAssertTrue(
            text.contains("ObjectTreeMenuTarget.resolve("),
            "「作用在哪一行」必须交给纯函数 `ObjectTreeMenuTarget.resolve` —— 结论要能被判据直接断言"
        )

        // ② 解析的住处（第 110 轮搬过去的）：体内必须仍是「悬停优先」，并且兜底到「已选中那一行」。
        let menu = try source("App/Views/ObjectTreeContextMenu.swift")
        guard let declaration = menu.range(of: "static func resolve(") else {
            return XCTFail("找不到 `ObjectTreeMenuTarget.resolve` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(menu[declaration.lowerBound...].prefix(1_200))
        XCTAssertTrue(
            body.contains("if let hoveredRowID,"),
            "悬停命中时必须优先用悬停行 —— 否则会退回「点数据库却弹服务器菜单」那个老毛病"
        )
        XCTAssertTrue(
            body.contains("$0.object.id == hoveredRowID"),
            "悬停行要按行 id 取回**对象**（不是拿悬停盒子里的别的东西）"
        )
        XCTAssertTrue(
            body.contains("guard let selected,") && body.contains("$0.object.id == selected.id"),
            "悬停没命中要兜底到「已选中那一行」：右键之前必然是左键点过它"
        )
        XCTAssertTrue(
            body.contains("!row.isGroupHeader"),
            "分组表头那一行不该拿到菜单（它是列表分组行，不是对象）"
        )
        XCTAssertTrue(
            body.contains("ObjectTreeActions.hasContextMenu("),
            "「这一行有没有菜单」要问 Core 的规则，不许在视图里另写一份类型判断"
        )

        // ③ 点击本身就是「指针在这一行」的铁证：单击与双击都要写悬停盒子（连 onHover 共 ≥3 处写入）。
        let writes = text.components(separatedBy: "hoverBox.rowID = row.object.id").count - 1
        XCTAssertGreaterThanOrEqual(
            writes, 3,
            "单击与双击都要顺手写悬停盒子（当前只有 \(writes) 处写入）—— 否则手快的人点完立刻右键还是空菜单"
        )
    }
}
