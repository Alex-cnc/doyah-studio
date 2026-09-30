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
///
/// ## 锚点归位二（2026-09-30，修队列 `L-103` 的 10 条 HEAD 红灯）
///
/// 2026-09-29 23:25–23:36 的交互会话把右键**交给 AppKit 捕获器自己给出**
/// （`ObjectTreeRightClick.swift::menu(for:)` → `ObjectTreeAppKitMenu.build(object: row.object …)`），
/// **整树兜底菜单与「视图里调 `resolve`」一起消失了** ⇒ 原先那条「视图必须调 `ObjectTreeMenuTarget.resolve`」
/// 判红。归位口径：**右键的目标不再由「悬停 / 上次选中」解析，而是命中行自己的对象 ——
/// 这比原判据要的更强**，所以那条断言改成它的结构性版本（生产路径不许出现 `resolve(` /
/// `menuTargetObject`），`resolve` 本体仍留在盘上、仍由上面那份探针的行为判据守着（作为
/// 「菜单内容与规则」的可渲染判据）。
final class ObjectTreeMenuConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testContextMenuTargetSurvivesRebuildClearingHover() throws {
        let text = try source("App/Views/ObjectTreeView.swift")

        // ① 菜单内容与作用行都走「那份唯一出处」，且目标必须经 `menuTargetObject`（悬停行 + 兜底）
        //    —— 只看悬停盒子的话，重建补的假 mouseExited 会让菜单变空。
        // ① 菜单内容与可用性仍只认**一个出处**：SwiftUI 渲染（`ObjectTreeContextMenu.items`，
        //    探针在渲染它）与 AppKit 渲染（`ObjectTreeAppKitMenu.build`，界面真正弹的那份）
        //    都必须由 Core 的 `ObjectTreeActions.isAvailable` 决定项的出现与否。
        let appKitMenu = try source("App/Views/ObjectTreeAppKitMenu.swift")
        XCTAssertTrue(
            appKitMenu.contains("ObjectTreeActions.isAvailable("),
            "AppKit 那份菜单必须问 Core 的 `ObjectTreeActions.isAvailable` —— 不许另写一套类型判断"
        )
        XCTAssertTrue(
            text.contains("ObjectTreeAppKitMenu.build("),
            "每一行都要把自己交给 AppKit 菜单构造器（界面真正弹的就是这一份）"
        )
        XCTAssertTrue(
            try source("App/Views/ObjectTreeContextMenu.swift").contains("static func items("),
            "SwiftUI 那份渲染（探针在用）必须保留 —— 它是菜单内容的可渲染判据"
        )
        // ② 菜单**挂在每一行上**（2026-09-29 需求提出者第三次投诉后的定案），
        //    整树那份"兜底菜单"已删除：它按悬停/上次选中算目标，什么都没选时会弹出一张**错的**菜单
        //    （需求提出者原话：「每次在没任何对象被选点情况点右键菜单，出来的是一个错误菜单，
        //    只有点第二次还会正常出现右键菜单」）。行级菜单每行自带自己的对象 ⇒ 不存在"目标算错"这一说。
        XCTAssertTrue(
            text.contains("object: row.object"),
            "每一行的菜单内容必须直接用它自己的 `row.object`"
        )
        XCTAssertFalse(
            text.contains("object: menuTargetObject"),
            "不许再有整树兜底菜单 —— 它就是「没选对象时弹出错菜单」的来源"
        )
        XCTAssertTrue(
            try source("App/Views/ObjectTreeRightClick.swift").contains("override func menu(for event: NSEvent) -> NSMenu?"),
            "捕获器必须自己给出菜单（AppKit 取 superview 链上第一个非 nil 的 menu(for:)）"
        )
        // 归位二（2026-09-30）：右键的目标**不再经过解析**，而是命中行自己的对象（见上一条 `object: row.object`）。
        // 原断言要的是「解析要能被判据直接断言」；新的结构性版本更强 —— 生产路径里**不许出现解析**：
        XCTAssertFalse(
            text.contains("ObjectTreeMenuTarget.resolve("),
            "生产路径不许再按「悬停 / 上次选中」解析菜单目标 —— 那正是整树兜底菜单与「点数据库却弹服务器菜单」的来源"
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

        // ③ 归位二（2026-09-30）：老修法是「点一下顺手把悬停盒子写成被点的那一行」这种**记账式兜底**；
        //    行级 AppKit 菜单之后，右键走的是**命中行自己**的对象、整条路不读悬停记录 —— 结构性修法，更强。
        //    代价：`hoverBox` 如今只写不读（生产路径没有读者）⇒ 已如实登记为队列 `L-119`，不在这里钉死。
        XCTAssertTrue(
            text.contains("makeMenu: {") && text.contains("object: row.object"),
            "每一行的菜单必须直接用它自己的 `row.object` —— 右键不经过悬停记录"
        )
    }
}
