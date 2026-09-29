import Foundation
import XCTest

/// 「右键挂在**每一行**上，不是整棵树一份」（`FR-META-14` 的形态判据）。
///
/// 2026-09-29 需求提出者实测原话：「直接点右键几乎无法选择任意对象，要先鼠标左键点一个对象才有几率
/// 右键打开，很难选择到数据对象」。根因：整棵树渲染成**一个** `List` 行（为了行距可控），
/// 右键菜单也只挂一份、目标由「悬停记录」在**呈现那一刻**算 —— 而整树重算（一选中就重算）之后
/// SwiftUI 会补一个假的 `mouseExited` 把悬停记录清掉，于是必须先左键点一下（把行钉进兜底）才行。
///
/// 判据形状：`ForEach(visibleRows)` 的闭包里必须**直接**给 `rowView(row)` 挂 `.contextMenu`，
/// 且用的是 `row.object`（当行自己的对象）—— 谁再把整树那一份当成唯一入口，这条就红。
final class ObjectTreeRowMenuConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testEveryRowCarriesItsOwnContextMenu() throws {
        let text = try source("App/Views/ObjectTreeView.swift")

        guard let loop = text.range(of: "ForEach(visibleRows) { row in") else {
            return XCTFail("找不到 `ForEach(visibleRows)` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(text[loop.lowerBound...].prefix(900))

        XCTAssertTrue(body.contains("rowView(row)") && body.contains(".contextMenu"),
                      "每一行都要挂自己的 `.contextMenu`；整树只剩一份 = 右键又要靠悬停记录（老毛病）")
        XCTAssertTrue(body.contains("object: row.object"),
                      "行级菜单的目标必须是**这一行自己的对象**（`row.object`），不能是全局解析出来的目标")
    }
    /// 点击区必须铺满整行 —— 只覆盖内容宽度时「标签右边那一截」点不到，表现就是「经常选不中」。
    func testRowHitAreaSpansFullWidth() throws {
        let text = try source("App/Views/ObjectTreeView.swift")

        guard let shape = text.range(of: ".contentShape(Rectangle())", options: .backwards) else {
            return XCTFail("找不到行的 `.contentShape(Rectangle())` —— 判据锚点变了")
        }
        let before = String(text[text.startIndex..<shape.lowerBound].suffix(400))
        XCTAssertTrue(before.contains(".frame(maxWidth: .infinity"),
                      "行的命中区要先铺满宽度（`maxWidth: .infinity`）再 `contentShape`，否则标签右侧的空白点不到")
    }
    /// **右键归属交给 AppKit 自己判**（不碰任何坐标）：每一行自己接右键。
    ///
    /// 2026-09-29 两轮坐标换算都栽了：第一版把左下原点当左上 ⇒ 静静不生效；
    /// 第二版按屏幕坐标换算能命中，但**每行差一行**（需求提出者：「每次都选到下面的对象去了」）。
    /// 结论：行的归属是 AppKit `hitTest` / `menu(for:)` 的本职，不要自己算。
    func testRightClickIsOwnedByEachRowNotByCoordinates() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("RowRightClickCatcher("),
                      "每一行都要挂自己的右键捕获器")
        XCTAssertTrue(view.contains("ObjectTreeAppKitMenu.build("),
                      "捕获器要注入按本行对象现建的 AppKit 菜单（`ObjectTreeAppKitMenu.build`）")
        XCTAssertTrue(view.contains("appState.selectTreeObject(row.object)"),
                      "捕获到右键就把那一行设为选中")
        XCTAssertFalse(view.contains("RightClickRowSelector("),
                       "不许再退回「指针坐标 ↔ 行框」那套 —— 两轮都错在坐标系/差一行")

        let helper = try source("App/Views/ObjectTreeRightClick.swift")
        XCTAssertTrue(helper.contains("override func hitTest"), "用 hitTest 精确控制「只接右键」")
        XCTAssertTrue(helper.contains("NSApp.currentEvent?.type == .rightMouseDown ? self : nil"),
                      "只认右键；左键必须返回 nil 放行给 SwiftUI，否则行选择与展开箭头全被挡")
        XCTAssertTrue(helper.contains("override func menu(for event: NSEvent) -> NSMenu?"),
                      "命中视图必须**自己实现 menu(for:)** —— 否则 AppKit 会问到侧栏连接行那份「断开连接」")
        XCTAssertTrue(helper.contains("return makeMenu?()"),
                      "menu(for:) 必须返回本行的 NSMenu（不是 nil、也不是别人的）")
        XCTAssertTrue(helper.contains("DOYAH_TREE_RIGHTCLICK_DEBUG"), "无界面权限时的取证口子")
    }
    /// **行级跳过重算**（队列 `L-90` 未完成的那半，2026-09-29 需求提出者选定「B：彻底根治」）。
    ///
    /// 现场：**左键选中比右键还慢** —— 左键改选中态 ⇒ 整棵树重算，几十行全部重建 body。
    /// 修法：行渲染抽成独立 `Equatable` 视图 + `.equatable()`（相等就不重算 body），
    /// 并且 `==` 必须**排除闭包**（每次重建都是新闭包，比了就永远不相等 = 白优化）。
    func testRowContentSkipsRebuildWhenUnchanged() throws {
        let rows = try source("App/Views/ObjectTreeRows.swift")
        XCTAssertTrue(rows.contains("struct ObjectTreeVisibleRow: Identifiable, Equatable"),
                      "行模型要 Equatable —— 否则行渲染体没法做相等比较")
        XCTAssertTrue(rows.contains("struct ObjectTreeRowContent: View, Equatable"),
                      "行渲染体必须独立成 View 并 Equatable")
        XCTAssertTrue(rows.contains("static func == (lhs: ObjectTreeRowContent, rhs: ObjectTreeRowContent) -> Bool"),
                      "相等比较要显式写出来（默认合成会把闭包也比进去）")
        XCTAssertTrue(rows.contains("`onToggle` 刻意不参与比较"),
                      "闭包必须排除在相等比较之外，否则永远不相等、等于没优化")
        XCTAssertTrue(rows.contains("bodyEvaluations"),
                      "要留取证计数器：右键日志会打出「距上次右键重算了几次 body」")

        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("ObjectTreeRowContent(") && view.contains(".equatable()"),
                      "行必须走 `ObjectTreeRowContent(...).equatable()`")
        XCTAssertFalse(view.contains("private func color(for kind: DatabaseObject.Kind)"),
                       "按类型上色已搬进行渲染体（`ObjectTreeRowContent.color`）—— 视图里不要再留一份")
    }
    /// **展开只走双击与右箭头，绝不走单击**（2026-09-29 需求提出者原话）：
    /// 「单击选择某个对象时不要去查数据并自动展开下一级，只有用户双击或选择前面的右箭头才展开，
    /// 不然体验真的很差」。原先单击既选中又展开 ⇒ 每点一下都发一条元数据查询 + 整树重算。
    func testSingleClickSelectsOnlyAndNeverExpands() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        guard let single = view.range(of: ".onTapGesture {") else {
            return XCTFail("找不到单击手势 —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let singleBody = String(view[single.lowerBound...].prefix(700))
        XCTAssertTrue(singleBody.contains("appState.selectTreeObject(row.object)"),
                      "单击必须选中")
        XCTAssertFalse(singleBody.contains("toggle(row.object)"),
                       "单击**不许**展开（会连带发元数据查询 + 整树重算）")

        guard let double = view.range(of: ".onTapGesture(count: 2) {") else {
            return XCTFail("找不到双击手势 —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let doubleBody = String(view[double.lowerBound...].prefix(700))
        XCTAssertTrue(doubleBody.contains("toggle(row.object)"),
                      "双击必须展开（它是除右箭头之外的唯一展开入口）")
    }
}
