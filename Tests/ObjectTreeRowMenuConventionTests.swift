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
}
