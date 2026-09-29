import Foundation
import XCTest

/// 「右键生成的语句，页签要记下来源表」—— 结果格的内联编辑（FR-DATA-04）只认 `QueryTab.sourceTable`。
///
/// 2026-09-29 人工点验第 3 条抓到的真缺陷：对象树右键「浏览前 N 行」直接生成 SQL 进编辑器，
/// 却**不带来源表** ⇒ 执行完点「编辑」被拒（提示「这个结果来自手写 SQL，无法确定来源表」）。
/// 同一件事走面板那条路（右键「按条件浏览…」）是带来源表的 —— **两条入口必须一致**。
final class TreeActionProvenanceConventionTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    /// 右键那条：`browseRows` 单独分支并带上来源表；模板类动作**不带**（执行 INSERT 的结果不是这张表的行集）。
    func testTreeBrowseActionCarriesSourceTable() throws {
        let text = try source("App/AppState.swift")

        guard let function = text.range(of: "func performTreeAction(") else {
            return XCTFail("找不到 `performTreeAction` —— 判据锚点变了，请更新这条判据而不是删掉它")
        }
        let body = String(text[function.lowerBound...].prefix(8000))
        guard let tail = body.range(of: "ObjectTreeActions.sql(for: action,") else {
            return XCTFail("找不到 `performTreeAction` 里生成 SQL 的那一段")
        }
        let segment = String(body[tail.lowerBound...].prefix(900))

        XCTAssertTrue(segment.contains("if action == .browseRows"),
                      "「浏览前 N 行」要单独分支：只有它带来源表（模板类动作不能带，否则结果格会误判成可编辑）")
        XCTAssertTrue(segment.contains("source: DatabaseObjectRef(schema: object.schema, name: object.name)"),
                      "「浏览前 N 行」必须把来源表写进页签 —— 少了这句，执行完的内联编辑就被拒")
    }

    /// 面板那条：一直是带来源表的。两条入口不许一条带、一条不带。
    func testBrowsePanelCarriesSourceTable() throws {
        let text = try source("App/AppState.swift")

        guard let function = text.range(
            of: "func browseRows(_ object: DatabaseObject, filter: RowBrowsingQuery.Filter)"
        ) else {
            return XCTFail("找不到浏览面板的确认入口 `browseRows(_:filter:)`")
        }
        let body = String(text[function.lowerBound...].prefix(900))
        XCTAssertTrue(body.contains("source: DatabaseObjectRef(schema: object.schema, name: object.name)"),
                      "面板「按条件浏览…」那条路必须继续带来源表 —— 它是 FR-DATA-04 的正式入口")
    }
}
