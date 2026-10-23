import XCTest
@testable import DoyahCore

/// 「预计影响行数」的判据（§9.1.16：审批单要给影响面）。
///
/// 三面：① **只包 DML**（只读语句不估 —— 界面上该写「不适用」而不是「0 行」）；
/// ② **不执行目标语句**（不带 `ANALYZE`，多语句一律拒绝）；
/// ③ **只认优化器给的数**（解析 PG 的 `EXPLAIN (FORMAT JSON)`，读不出就如实说读不出）。
final class AgentPlanRowsTests: XCTestCase {

    // MARK: - ① 只包 DML

    func testWrapsDataChangingStatementsOnly() {
        XCTAssertEqual(AgentPlanRows.explainStatement(for: "UPDATE t SET a = 1 WHERE id < 10"),
                       "EXPLAIN (FORMAT JSON) UPDATE t SET a = 1 WHERE id < 10")
        XCTAssertEqual(AgentPlanRows.explainStatement(for: "  delete from t where id = 1 ;  "),
                       "EXPLAIN (FORMAT JSON) delete from t where id = 1")
        XCTAssertNotNil(AgentPlanRows.explainStatement(for: "INSERT INTO t (a) SELECT a FROM s"))
        XCTAssertNotNil(AgentPlanRows.explainStatement(for: "MERGE INTO t USING s ON t.id = s.id WHEN MATCHED THEN DELETE"))

        // 只读语句**不估**：没有「会影响多少行」这回事
        for readonly in ["SELECT * FROM t", "WITH x AS (SELECT 1) SELECT * FROM x", "SHOW search_path", ""] {
            XCTAssertNil(AgentPlanRows.explainStatement(for: readonly), "不该给只读语句包 EXPLAIN：\(readonly)")
        }
    }

    // MARK: - ② 不执行目标语句 / 不接受多语句

    /// 多语句：`EXPLAIN` 只作用第一条，后半截会原样跑 —— 一律拒绝。
    func testRejectsMultipleStatements() {
        XCTAssertNil(AgentPlanRows.explainStatement(for: "UPDATE t SET a = 1; DROP TABLE t"))
        XCTAssertNil(AgentPlanRows.explainStatement(for: "UPDATE t SET a = 1; DELETE FROM t"))
    }

    /// 生成的语句里**不许出现 ANALYZE**（带它就会真的执行目标语句）。
    func testNeverAsksForAnalyze() {
        let statement = AgentPlanRows.explainStatement(for: "DELETE FROM t WHERE id = 1")
        XCTAssertNotNil(statement)
        XCTAssertFalse(statement!.uppercased().contains("ANALYZE"), "带 ANALYZE 的 EXPLAIN 会真的改数据")
    }

    // MARK: - ③ 只认优化器给的数

    /// 真·PostgreSQL `EXPLAIN (FORMAT JSON)` 形状（字段与顺序照服务端输出）。
    func testReadsPlanRowsFromPostgresJSON() {
        let json = """
        [
          {
            "Plan": {
              "Node Type": "Update",
              "Parallel Aware": false,
              "Relation Name": "t",
              "Alias": "t",
              "Startup Cost": 0.00,
              "Total Cost": 12.34,
              "Plan Rows": 42,
              "Plan Width": 8,
              "Plans": [
                {
                  "Node Type": "Seq Scan",
                  "Relation Name": "t",
                  "Plan Rows": 42,
                  "Plan Width": 8
                }
              ]
            }
          }
        ]
        """
        XCTAssertEqual(AgentPlanRows.rows(fromExplainJSON: json), 42)
        XCTAssertEqual(AgentPlanRows.estimate(json: json), .rows(42))
    }

    /// **实测形状（2026-10-23 · 217 上的 PG 18.6，`UPDATE "t" SET "id"="id" WHERE "id" IS NOT NULL`）**：
    /// 根节点是 `ModifyTable`，它自己的 `Plan Rows` 恒为 **0**（不带 `RETURNING` ⇒ 节点不输出行），
    /// 真正「会改多少行」的预估在**子节点**（这里是 `Seq Scan` 的 500）。
    /// 只读根节点会稳定报「0 行」—— 那是最危险的一种假数（人看到 0 就放心批准）。
    func testModifyTableReadsChildRowsWhenRootIsZero() {
        let json = """
        [
          {
            "Plan": {
              "Node Type": "ModifyTable",
              "Operation": "Update",
              "Parallel Aware": false,
              "Async Capable": false,
              "Relation Name": "t",
              "Alias": "t",
              "Startup Cost": 0.00,
              "Total Cost": 8.00,
              "Plan Rows": 0,
              "Plan Width": 0,
              "Disabled": false,
              "Plans": [
                {
                  "Node Type": "Seq Scan",
                  "Parent Relationship": "Outer",
                  "Parallel Aware": false,
                  "Async Capable": false,
                  "Relation Name": "t",
                  "Alias": "t",
                  "Startup Cost": 0.00,
                  "Total Cost": 8.00,
                  "Plan Rows": 500,
                  "Plan Width": 10,
                  "Disabled": false
                }
              ]
            }
          }
        ]
        """
        XCTAssertEqual(AgentPlanRows.estimate(json: json), .rows(500),
                       "ModifyTable 根 0 时要取子节点的预估（真库实测 500）")
    }

    /// 带 `RETURNING` 时 `ModifyTable` 自己就输出影响行数 ⇒ 根节点非 0，直接用根。
    func testModifyTableWithReturningUsesRootRows() {
        let json = """
        [{"Plan": {"Node Type": "ModifyTable", "Operation": "Delete", "Plan Rows": 42,
                   "Plans": [{"Node Type": "Seq Scan", "Plan Rows": 42}]}}]
        """
        XCTAssertEqual(AgentPlanRows.rows(fromExplainJSON: json), 42)
    }

    /// `0` 是合法值（一条都不命中）——不许被当成「没读到」。
    func testZeroRowsIsAValidReading() {
        let json = #"[{"Plan": {"Node Type": "Delete", "Plan Rows": 0}}]"#
        XCTAssertEqual(AgentPlanRows.estimate(json: json), .rows(0))
    }

    /// 驱动把数字读成文本也认（有的封装会这样）。
    func testAcceptsNumericStrings() {
        let json = #"[{"Plan": {"Node Type": "Insert", "Plan Rows": "7"}}]"#
        XCTAssertEqual(AgentPlanRows.rows(fromExplainJSON: json), 7)
    }

    /// 没有答复 / 答复里没有 `Plan Rows` —— 两种都**如实说估不出来**，别报 0。
    func testUnreadableAnswersSaySoInsteadOfZero() {
        XCTAssertEqual(AgentPlanRows.estimate(json: nil), .unavailable("noAnswer"))
        XCTAssertEqual(AgentPlanRows.estimate(json: "   "), .unavailable("noAnswer"))
        XCTAssertEqual(AgentPlanRows.estimate(json: ""), .unavailable("noAnswer"))
        XCTAssertEqual(AgentPlanRows.estimate(json: "not json at all"), .unavailable("parseFailed"))
        XCTAssertEqual(AgentPlanRows.estimate(json: #"[{"Plan": {"Node Type": "Update"}}]"#),
                       .unavailable("parseFailed"))
        XCTAssertEqual(AgentPlanRows.estimate(json: #"[]"#), .unavailable("parseFailed"))
        XCTAssertEqual(AgentPlanRows.rows(fromExplainJSON: #"[{"Plan": {"Plan Rows": 3}}]"#), 3,
                       "只给 Plan 与 Plan Rows 也能读（简化封装）")
    }
}
