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
    /// **右键即选中**：指针在哪一行，右键就把那一行设为选中。
    ///
    /// 2026-09-29 需求提出者第二次实测：「当有任意一个对象被选中了，再右键别的对象就选不中了」——
    /// 根因是行级 hover 状态在整树重算后会被清空，指针没动就不再触发 `onHover`
    /// ⇒「鼠标底下那一行」是空的 ⇒ 菜单退回"上次左键点过的那一行"。指针位置才是可靠事实。
    func testRightClickSelectsRowUnderPointer() throws {
        let view = try source("App/Views/ObjectTreeView.swift")
        XCTAssertTrue(view.contains("RightClickRowSelector("),
                      "树上必须挂右键选中器（按指针位置定位行）")
        XCTAssertTrue(view.contains("ObjectTreeRowFrameRecorder(id:"),
                      "每一行都要记自己在窗口坐标里的框 —— 没有框就没法按指针命中")
        XCTAssertTrue(view.contains("appState.selectTreeObject(row.object)"),
                      "右键命中后必须把那一行设为选中，菜单内容才会跟着它走")

        let helper = try source("App/Views/ObjectTreeRightClick.swift")
        XCTAssertTrue(helper.contains("addLocalMonitorForEvents(matching: [.rightMouseDown])"),
                      "用本地事件监听读指针位置（进程内、零授权）；别退回行级 hover")
        XCTAssertTrue(helper.contains("return event"),
                      "监听器只读事件不改事件：必须 `return event`，否则菜单弹不出来")
        XCTAssertTrue(helper.contains("func rowID(at point: CGPoint"),
                      "命中判定要抽成纯函数，判据才能直接断言")
    }
}
