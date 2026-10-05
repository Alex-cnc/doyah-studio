import XCTest
@testable import DoyahCore

/// FR-EXEC-14：**这次跑哪一段**。
///
/// 口径（2026-09-27 需求提出者拍板）：
/// - 编辑器里有选区 → 只跑选中的那段；
/// - 没有选区 → 跑整篇。
///
/// 原来那三档（整篇 / 光标所在语句 / 选中片段）是**用户要先设一次**的开关，
/// 需求提出者裁定为多此一举（原话：「用户没有选择某条 SQL 时就执行编辑框里所有 SQL，
/// 否则就是执行用户选择，并不需要用户还去设置一下」）⇒ 菜单与三档一起删掉，
/// 判定收进 `resolve` 一处。本文件跟着重写：光标定位那一族用例随档位一起消失。
final class ExecutionScopeTests: XCTestCase {

    private let sql = """
    -- 两条独立语句
    SELECT 1;
    SELECT * FROM orders WHERE id = 2;
    UPDATE orders SET total = 0 WHERE id = 3;
    """

    // MARK: - 没选区 ⇒ 整篇

    func testNoSelectionRunsWholeText() {
        for selection in [nil, NSRange(location: 5, length: 0)] {
            let resolution = ExecutionScope.resolve(text: sql, selection: selection)

            XCTAssertEqual(resolution.source, .wholeScript, "没选区时跑整篇（光标在哪不影响）")
            XCTAssertEqual(resolution.sql, sql)
            XCTAssertNil(resolution.issue)
        }
    }

    func testEmptyTextReportsIssue() {
        let resolution = ExecutionScope.resolve(text: "   \n  ")

        XCTAssertEqual(resolution.issue, .emptyText)
        XCTAssertTrue(resolution.sql.isEmpty)
    }

    // MARK: - 有选区 ⇒ 只跑选中的那段

    func testSelectionRunsOnlySelectedFragment() {
        let ns = sql as NSString
        let target = "UPDATE orders SET total = 0 WHERE id = 3;"

        let resolution = ExecutionScope.resolve(text: sql, selection: ns.range(of: target))

        XCTAssertEqual(resolution.source, .selection)
        XCTAssertEqual(resolution.sql, target)
        XCTAssertNil(resolution.issue)
    }

    /// 多语句脚本里选中其中一条：**只跑那一条**（其余不动，这是用户要的语义）。
    func testSelectingOneStatementOutOfManyRunsOnlyThatOne() {
        let text = "SELECT * FROM tx_demo;\nDELETE FROM tx_demo;"
        let ns = text as NSString

        let resolution = ExecutionScope.resolve(text: text, selection: ns.range(of: "DELETE FROM tx_demo;"))

        XCTAssertEqual(resolution.source, .selection)
        XCTAssertEqual(resolution.sql, "DELETE FROM tx_demo;")
        XCTAssertFalse(resolution.sql.contains("SELECT"), "选中 delete 就不该把 select 也带上")
    }

    /// 选区跨两条语句：两条都跑（选中什么就跑什么）。
    func testSelectionSpanningTwoStatementsRunsBoth() {
        let text = "SELECT 1;\nSELECT 2;"
        let ns = text as NSString

        let resolution = ExecutionScope.resolve(text: text, selection: NSRange(location: 0, length: ns.length))

        XCTAssertEqual(resolution.source, .selection)
        XCTAssertEqual(resolution.sql, text)
    }

    func testSelectionTrimsSurroundingWhitespace() {
        let ns = sql as NSString
        let range = ns.range(of: "SELECT 1;")

        let resolution = ExecutionScope.resolve(text: sql, selection: range)

        XCTAssertEqual(resolution.sql, "SELECT 1;")
    }

    /// 选中的内容全是空白：**不静默改成跑整篇**（那等于把一次小操作放大成整篇脚本）。
    func testWhitespaceOnlySelectionReportsIssueInsteadOfRunningEverything() {
        let text = "SELECT 1;      SELECT 2;"

        let resolution = ExecutionScope.resolve(
            text: text,
            selection: NSRange(location: 9, length: 6)
        )

        XCTAssertEqual(resolution.issue, .emptySelection)
        XCTAssertTrue(resolution.sql.isEmpty)
        XCTAssertNotEqual(resolution.sql, text, "宁可什么都不跑，也不许悄悄跑整篇")
    }

    /// 选区越过文末时按实际长度夹取，不越界崩溃。
    func testSelectionIsClampedToTextLength() {
        let text = "SELECT 1;"

        let resolution = ExecutionScope.resolve(
            text: text,
            selection: NSRange(location: 0, length: 9_999)
        )

        XCTAssertEqual(resolution.sql, text)
    }

    /// 越界选区（理论上不该出现：它来自显示中的编辑器）按「没有选区」处理 ——
    /// 宁可跑整篇，也不去猜一段可能的旧偏移。
    func testOutOfBoundsSelectionIsTreatedAsNoSelection() {
        let resolution = ExecutionScope.resolve(
            text: sql,
            selection: NSRange(location: 10_000, length: 5)
        )

        XCTAssertEqual(resolution.source, .wholeScript)
        XCTAssertEqual(resolution.sql, sql)
        XCTAssertNil(resolution.issue)
    }

    // MARK: - 与高危保护衔接

    /// 判定出来的 SQL 直接喂给 Safe Mode：**只对真正要跑的那段**判定。
    func testResolvedSQLFeedsSafetyCheck() {
        let text = "SELECT 1;\nDELETE FROM orders;"
        let ns = text as NSString

        // 什么都没选 ⇒ 整篇（含 DELETE）⇒ 必须被拦
        let whole = ExecutionScope.resolve(text: text)
        XCTAssertFalse(
            ExecutionSafety.check(sql: whole.sql, databaseType: .postgresql, policy: .default).isAllowed
        )

        // 只选中 SELECT 那段 ⇒ 只有它会被检查 ⇒ 放行
        let onlySelect = ExecutionScope.resolve(
            text: text,
            selection: ns.range(of: "SELECT 1;")
        )
        XCTAssertTrue(
            ExecutionSafety.check(sql: onlySelect.sql, databaseType: .postgresql, policy: .default).isAllowed
        )
    }
}
