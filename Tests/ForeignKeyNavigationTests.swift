import XCTest
@testable import DoyahCore

/// 外键引用导航（FR-DATA-06）。
///
/// 需求点名的验收是"**有外键元数据时才呈现入口；没有目标就不显示**"，
/// 所以重点在解析准确性（别把 CHECK 当外键）与"两个方向都能找到"。
final class ForeignKeyNavigationTests: XCTestCase {

    private let dialect: SQLDialect = SQLDialectFactory.make(for: .postgresql)

    private func edge(
        _ name: String = "fk_1",
        from: String = "order_items",
        column: String = "order_id",
        to: String = "orders",
        targetColumn: String = "id"
    ) -> ForeignKeyNavigation.Edge {
        ForeignKeyNavigation.Edge(
            constraintName: name,
            fromTable: from,
            fromSchema: "public",
            columns: [column],
            toTable: to,
            toSchema: "public",
            referencedColumns: [targetColumn]
        )
    }

    // MARK: 解析

    func testParsesTypicalForeignKeyDefinition() {
        let parsed = ForeignKeyNavigation.parseEdge(
            constraintName: "order_items_order_id_fkey",
            kind: "f",
            definition: "FOREIGN KEY (order_id) REFERENCES public.orders(id)",
            table: "order_items",
            schema: "public"
        )
        XCTAssertEqual(parsed?.columns, ["order_id"])
        XCTAssertEqual(parsed?.toTable, "orders")
        XCTAssertEqual(parsed?.referencedColumns, ["id"])
        XCTAssertEqual(parsed?.toSchema, "public")
    }

    func testParsesCompositeForeignKey() {
        let parsed = ForeignKeyNavigation.parseEdge(
            constraintName: "c",
            kind: "f",
            definition: "FOREIGN KEY (tenant_id, order_id) REFERENCES orders(tenant_id, id)",
            table: "lines",
            schema: nil
        )
        XCTAssertEqual(parsed?.columns, ["tenant_id", "order_id"])
        XCTAssertEqual(parsed?.referencedColumns, ["tenant_id", "id"])
    }

    /// **CHECK / UNIQUE 不是外键** —— 当成外键会生成跳到不存在列的语句。
    func testNonForeignKeyConstraintIsIgnored() {
        XCTAssertNil(ForeignKeyNavigation.parseEdge(
            constraintName: "ck", kind: "c", definition: "CHECK ((amount > 0))",
            table: "t", schema: nil
        ))
        XCTAssertNil(ForeignKeyNavigation.parseEdge(
            constraintName: "u", kind: "u", definition: "UNIQUE (email)", table: "t", schema: nil
        ))
    }

    func testMalformedDefinitionReturnsNil() {
        XCTAssertNil(ForeignKeyNavigation.parseEdge(
            constraintName: "fk", kind: "f", definition: "FOREIGN KEY (a) REFERENCES", table: "t", schema: nil
        ))
        // 两侧列数不一致：不猜，直接拒
        XCTAssertNil(ForeignKeyNavigation.parseEdge(
            constraintName: "fk", kind: "f", definition: "FOREIGN KEY (a, b) REFERENCES other(id)",
            table: "t", schema: nil
        ))
    }

    func testQuotedIdentifiersAreUnwrapped() {
        let parsed = ForeignKeyNavigation.parseEdge(
            constraintName: "fk", kind: "f",
            definition: "FOREIGN KEY (\"order id\") REFERENCES \"My Schema\".\"orders\"(\"id\")",
            table: "lines", schema: nil
        )
        XCTAssertEqual(parsed?.columns, ["order id"])
        XCTAssertEqual(parsed?.toTable, "orders")
        XCTAssertEqual(parsed?.toSchema, "My Schema")
    }

    // MARK: 两个方向

    func testForwardAndReverseAreBothFound() {
        let edges = [edge()]
        let forward = ForeignKeyNavigation.options(table: "order_items", column: "order_id", edges: edges)
        XCTAssertEqual(forward.count, 1)
        XCTAssertEqual(forward[0].direction, .forward)
        XCTAssertEqual(forward[0].targetTable, "orders")
        XCTAssertEqual(forward[0].targetColumn, "id")

        let reverse = ForeignKeyNavigation.options(table: "orders", column: "id", edges: edges)
        XCTAssertEqual(reverse.count, 1)
        XCTAssertEqual(reverse[0].direction, .reverse)
        XCTAssertEqual(reverse[0].targetTable, "order_items")
        XCTAssertEqual(reverse[0].targetColumn, "order_id")
    }

    /// 验收原文：**没有外键就不呈现入口**。
    func testNoOptionsWhenNoForeignKey() {
        XCTAssertFalse(ForeignKeyNavigation.hasOption(table: "logs", column: "id", edges: [edge()]))
        XCTAssertTrue(ForeignKeyNavigation.options(table: "order_items", column: "note", edges: [edge()]).isEmpty)
    }

    func testOptionTitlesAreStableAndReadable() {
        let options = ForeignKeyNavigation.options(
            table: "lines",
            column: "order_id",
            edges: [
                edge("fk_b", from: "lines", column: "order_id", to: "b_table", targetColumn: "id"),
                edge("fk_a", from: "lines", column: "order_id", to: "a_table", targetColumn: "id")
            ]
        )
        XCTAssertEqual(options.map(\.targetTable), ["a_table", "b_table"], "同方向内按标题排序（稳定）")
        XCTAssertTrue(options[0].title.contains("跳到被引用表"), options[0].title)
        XCTAssertTrue(options[0].title.contains("a_table"), options[0].title)
    }

    // MARK: 跳转查询

    func testNavigationQueryCarriesValueAndLimit() {
        let option = ForeignKeyNavigation.options(table: "order_items", column: "order_id", edges: [edge()])[0]
        let sql = ForeignKeyNavigation.query(option: option, value: "42", typeName: "integer", dialect: dialect)
        XCTAssertEqual(sql, "SELECT * FROM \"public\".\"orders\" WHERE \"id\" = 42 LIMIT 200;")
    }

    func testNavigationQueryQuotesTextValues() {
        let option = ForeignKeyNavigation.Option(
            direction: .forward, localColumn: "code", targetTable: "codes",
            targetSchema: nil, targetColumn: "code", constraintName: nil
        )
        let sql = ForeignKeyNavigation.query(option: option, value: "O'Brien", typeName: "text", dialect: dialect)
        XCTAssertTrue(sql.contains("'O''Brien'"), sql)
    }

    // MARK: 入口可见性（需求原文：存在外键元数据时才呈现入口）

    /// 只有「本表真的挂着外键」的列才进集合：别的表的边、别的 schema 的边都不许混进来。
    func testForwardColumnsOnlyCollectsThisTablesForeignKeyColumns() {
        let local = ForeignKeyNavigation.Edge(
            fromTable: "order_items", fromSchema: "public",
            columns: ["order_id", "sku"], toTable: "orders", toSchema: "public",
            referencedColumns: ["id", "sku"]
        )
        let otherSchema = ForeignKeyNavigation.Edge(
            fromTable: "order_items", fromSchema: "archive",
            columns: ["ghost_id"], toTable: "orders", toSchema: "archive",
            referencedColumns: ["id"]
        )
        let incoming = ForeignKeyNavigation.Edge(
            fromTable: "refunds", fromSchema: "public",
            columns: ["item_id"], toTable: "order_items", toSchema: "public",
            referencedColumns: ["id"]
        )
        let columns = ForeignKeyNavigation.forwardColumns(
            table: "ORDER_ITEMS",
            edges: [local, otherSchema, incoming],
            schema: "public"
        )
        XCTAssertEqual(columns, ["order_id", "sku"])
    }

    /// 元数据没读到（nil）⇒ 不露；读到了但这一列没有外键 ⇒ 不露；有 ⇒ 露。
    func testEntryIsVisibleOnlyWhenThatColumnHasAForeignKey() {
        XCTAssertFalse(ForeignKeyNavigation.entryVisible(jumpable: nil, clickedColumn: "order_id"))
        XCTAssertFalse(ForeignKeyNavigation.entryVisible(jumpable: [], clickedColumn: "order_id"))
        XCTAssertFalse(ForeignKeyNavigation.entryVisible(jumpable: ["order_id"], clickedColumn: nil))
        XCTAssertFalse(ForeignKeyNavigation.entryVisible(jumpable: ["order_id"], clickedColumn: "note"))
        XCTAssertTrue(ForeignKeyNavigation.entryVisible(jumpable: ["order_id"], clickedColumn: "order_id"))
        XCTAssertTrue(
            ForeignKeyNavigation.entryVisible(jumpable: ["order_id"], clickedColumn: "Order_ID"),
            "列名比较必须与 options(...) 同口径（大小写不敏感）"
        )
    }
}
