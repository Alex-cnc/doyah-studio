import XCTest
@testable import DoyahCore

/// 整表 / 整库导出的计划与账（`FR-STD-DB-IO-002`，2026-10-29 第七十批）。
///
/// 这一套只判**纯判定**：那条 `SELECT` 怎么拼、整库的文件名怎么取、逐表结局怎么记账。
/// 真取数与真写盘在 `CursorFetcher` / `ResultStreamWriter`（各有自己的套件），这里一条 IO 都不碰。
final class TableExportTests: XCTestCase {

    private let postgres = SQLDialectFactory.make(for: .postgresql)
    private let mysql = SQLDialectFactory.make(for: .mysql)

    // MARK: - 整表导出：那条 SELECT

    func testSelectSQLWithoutSchemaQuotesTableName() throws {
        let sql = try TableExport.selectSQL(table: "orders", schema: nil, dialect: postgres)
        XCTAssertEqual(sql, "SELECT * FROM \"orders\"")
    }

    func testSelectSQLWithSchemaQualifies() throws {
        let sql = try TableExport.selectSQL(table: "orders", schema: "public", dialect: postgres)
        XCTAssertEqual(sql, "SELECT * FROM \"public\".\"orders\"")
    }

    /// 合法的「引用名」不许被拒：`My Table` 在 PG 里是一张正常的表，
    /// 若拿 `isValidIdentifier`（首字符须字母 / 下划线）当闸门，这类表就永远导不出来。
    func testSelectSQLAcceptsLegalNamesWithSpaces() throws {
        let sql = try TableExport.selectSQL(table: "My Table", schema: nil, dialect: postgres)
        XCTAssertEqual(sql, "SELECT * FROM \"My Table\"")
    }

    /// 注入面钉在这里：名字里的双引号必须被双写、整体仍在引号内。
    func testSelectSQLEscapesEmbeddedQuotes() throws {
        let hostile = "a\"b; DROP TABLE users; --"
        let sql = try TableExport.selectSQL(table: hostile, schema: nil, dialect: postgres)
        XCTAssertEqual(sql, "SELECT * FROM \"a\"\"b; DROP TABLE users; --\"")
        // 反向守卫：语句里除了最外那对引号之外，任何 `"` 都必须成对出现，
        // 否则一次拼接就能从标识符里「跳出」到语句层面。
        let body = sql.replacingOccurrences(of: "SELECT * FROM ", with: "")
        XCTAssertTrue(body.hasPrefix("\""), body)
        XCTAssertTrue(body.hasSuffix("\""), body)
    }

    func testSelectSQLRejectsEmptyNameAndNUL() {
        XCTAssertThrowsError(try TableExport.selectSQL(table: "   ", schema: nil, dialect: postgres)) { error in
            XCTAssertEqual(error as? TableExport.Issue, .emptyTableName)
        }
        XCTAssertThrowsError(try TableExport.selectSQL(table: "bad\0name", schema: nil, dialect: postgres)) { error in
            XCTAssertEqual(error as? TableExport.Issue, .invalidIdentifier("bad\0name"))
        }
        XCTAssertThrowsError(
            try TableExport.selectSQL(table: "orders", schema: "bad\0schema", dialect: postgres)
        ) { error in
            XCTAssertEqual(error as? TableExport.Issue, .invalidIdentifier("bad\0schema"))
        }
    }

    /// 不带 schema 的方言（MySQL 走库而不是 schema）不许硬拼前缀。
    func testSelectSQLRespectsDialectSchemaSupport() throws {
        let sql = try TableExport.selectSQL(table: "orders", schema: "shop", dialect: mysql)
        XCTAssertEqual(sql, "SELECT * FROM `orders`")
    }

    /// **不加 `ORDER BY`** 是这条需求的性能口径（排序要把全量读进内存，正好毁掉流式）。
    func testSelectSQLDoesNotSort() throws {
        let sql = try TableExport.selectSQL(table: "orders", schema: nil, dialect: postgres)
        XCTAssertFalse(sql.uppercased().contains("ORDER BY"), sql)
    }

    // MARK: - 流式能力

    func testStreamingSupportedOnlyForPostgres() {
        XCTAssertTrue(TableExport.streamingSupported(.postgresql))
        XCTAssertFalse(TableExport.streamingSupported(.mysql))
        XCTAssertFalse(TableExport.streamingSupported(.gbase8a))
    }

    // MARK: - 取数裁定（CLI 与界面共用的那一处）

    /// PostgreSQL 走流式；这一条是**允许面**（只有拒绝面的判据会让「一律拒绝」看起来全绿）。
    func testDecisionStreamsOnPostgres() {
        XCTAssertEqual(TableExport.decision(for: .postgresql), .streaming)
        XCTAssertTrue(TableExport.decision(for: .postgresql).isStreaming)
    }

    /// 拒绝必须**带上认出来的类型**（CLI 靠它把「这个连接是 MySQL」说清楚，而不是一句「不支持」）。
    func testDecisionRejectsMySQLWithItsOwnType() {
        XCTAssertEqual(TableExport.decision(for: .mysql), .rejected(.streamingUnsupported(.mysql)))
        XCTAssertFalse(TableExport.decision(for: .mysql).isStreaming)
    }

    func testDecisionRejectsGBaseWithItsOwnType() {
        XCTAssertEqual(TableExport.decision(for: .gbase8a), .rejected(.streamingUnsupported(.gbase8a)))
        XCTAssertFalse(TableExport.decision(for: .gbase8a).isStreaming)
    }

    /// 两种非 PG 类型**不许压成同一个值**：压掉差别，命令行就分不清自己连的是谁。
    func testRejectedDecisionsKeepTheTwoNonPostgresTypesApart() {
        XCTAssertNotEqual(
            TableExport.decision(for: .mysql),
            TableExport.decision(for: .gbase8a)
        )
    }

    /// 布尔与裁定**必须同源**：`streamingSupported` 是 `decision` 的投影，逐个类型对账。
    /// 这条判据的用处是把「两处各写一份」钉死在编译产物之外 —— 谁把布尔改回自己算，这里就红。
    func testStreamingSupportedIsTheProjectionOfDecision() {
        for type in DatabaseType.allCases {
            XCTAssertEqual(
                TableExport.streamingSupported(type),
                TableExport.decision(for: type).isStreaming,
                "\(type.rawValue) 的两处口径不一致"
            )
        }
    }

    /// 拒绝理由要能落到一句可排查的话上（类型名在里面），不是「出错了」。
    func testRejectedDecisionCarriesAReadableReason() {
        guard case .rejected(let issue) = TableExport.decision(for: .mysql) else {
            return XCTFail("MySQL 必须被判成拒绝")
        }
        XCTAssertTrue(issue.description.contains("mysql"), issue.description)
        XCTAssertFalse(issue.description.isEmpty)
    }

    /// **方言必须随连接类型取**（第七十二批的口径）：同一句 `selectSQL` 在三种连接下按各自的
    /// 引用规则拼 —— 钉死一个方言时这条判据会红（两种非 PG 都拿不到反引号）。
    func testDialectFollowsTheConnectionType() throws {
        for type in DatabaseType.allCases {
            let dialect = SQLDialectFactory.make(for: type)
            XCTAssertEqual(dialect.databaseType, type, "\(type.rawValue) 拿到的方言不是它自己的")
            let sql = try TableExport.selectSQL(table: "orders", schema: nil, dialect: dialect)
            let expectedQuote = dialect.identifierQuote
            XCTAssertTrue(
                sql.contains("\(expectedQuote)orders\(expectedQuote)"),
                "\(type.rawValue) 的限定名没用它自己的引号：\(sql)"
            )
        }
    }

    // MARK: - 整库：文件名

    func testEntriesSanitizeUnsafeCharactersAndDeduplicate() {
        let entries = TableExport.entries(
            schema: "public",
            tables: ["a/b", "a:b", "normal"],
            format: .csv
        )
        XCTAssertEqual(entries.map(\.fileName), ["a_b.csv", "a_b-2.csv", "normal.csv"])
        XCTAssertEqual(entries.map(\.table), ["a/b", "a:b", "normal"])
    }

    func testEntriesKeepUnicodeAndAreDeterministic() {
        let first = TableExport.entries(schema: "public", tables: ["订单", "客户"], format: .json)
        let second = TableExport.entries(schema: "public", tables: ["订单", "客户"], format: .json)
        XCTAssertEqual(first.map(\.fileName), ["订单.json", "客户.json"])
        XCTAssertEqual(first, second)
    }

    func testSafeBaseNameHandlesDotNamesAndLeadingDot() {
        XCTAssertEqual(TableExport.safeBaseName(".."), "table")
        XCTAssertEqual(TableExport.safeBaseName(".hidden"), "_.hidden")
        XCTAssertEqual(TableExport.safeBaseName("   "), "table")
        XCTAssertEqual(TableExport.safeBaseName("My Table"), "My_Table")
    }

    // MARK: - 整库：名单（第七十一批）

    /// 表与视图都要导，其余节点跳过 —— 且**跳过的要能数出来**（不许静默少导）。
    func testDatabasePlanExportsTablesAndViewsAndSkipsOtherKinds() {
        let plan = TableExport.databasePlan(
            [
                .init(kind: .table, name: "orders", schema: "public"),
                .init(kind: .view, name: "v_orders", schema: "public"),
                .init(kind: .sequence, name: "orders_id_seq", schema: "public"),
                .init(kind: .function, name: "f_total", schema: "public"),
            ],
            format: .csv
        )
        XCTAssertEqual(plan.jobs.map(\.table), ["orders", "v_orders"])
        XCTAssertEqual(plan.jobs.map(\.isView), [false, true])
        XCTAssertEqual(plan.skipped.map(\.name), ["orders_id_seq", "f_total"])
        XCTAssertEqual(plan.skipped.map(\.kind), [.sequence, .function])
        XCTAssertEqual(plan.skippedCount, 2)
    }

    /// 同一个 schema 内不带前缀：文件名就是表名（用户按名字找文件，别加噪声）。
    func testDatabasePlanSingleSchemaKeepsPlainNames() {
        let plan = TableExport.databasePlan(
            [
                .init(kind: .table, name: "orders", schema: "public"),
                .init(kind: .table, name: "订单", schema: "public"),
            ],
            format: .json
        )
        XCTAssertFalse(plan.multiSchema)
        XCTAssertEqual(plan.jobs.map(\.fileName), ["orders.json", "订单.json"])
        XCTAssertEqual(plan.jobs.map(\.label), ["orders", "订单"])
    }

    /// 跨 schema 时必须带前缀：两个 `orders` 只靠 `-2` 后缀区分的话，
    /// 用户看不出哪个文件是哪张表。
    func testDatabasePlanMultiSchemaPrefixesFileNamesAndLabels() {
        let plan = TableExport.databasePlan(
            [
                .init(kind: .table, name: "orders", schema: "public"),
                .init(kind: .table, name: "orders", schema: "sales"),
            ],
            format: .tsv
        )
        XCTAssertTrue(plan.multiSchema)
        XCTAssertEqual(plan.jobs.map(\.fileName), ["public.orders.tsv", "sales.orders.tsv"])
        XCTAssertEqual(plan.jobs.map(\.label), ["public.orders", "sales.orders"])
        XCTAssertEqual(plan.jobs.map(\.schema), ["public", "sales"])
    }

    /// 树的两层展开可能把同一张表喂进来两次 ⇒ 只导一次（否则第二遍会占一个 `-2` 文件名，
    /// 用户以为库里多了一张表）。
    func testDatabasePlanDeduplicatesSameSchemaAndTable() {
        let plan = TableExport.databasePlan(
            [
                .init(kind: .table, name: "orders", schema: "public"),
                .init(kind: .table, name: "orders", schema: "public"),
            ],
            format: .csv
        )
        XCTAssertEqual(plan.jobs.count, 1)
        XCTAssertEqual(plan.jobs.map(\.fileName), ["orders.csv"])
        // 同名不同 schema 不是重复。
        let both = TableExport.databasePlan(
            [
                .init(kind: .table, name: "orders", schema: "public"),
                .init(kind: .table, name: "orders"),
            ],
            format: .csv
        )
        XCTAssertEqual(both.jobs.count, 2, "没有 schema 的那个是另一张表，不许被当成重复吃掉")
    }

    /// 表格名为空 ⇒ 跳过（记进 `skipped`），不许落出一个叫 `.csv` 的文件。
    func testDatabasePlanSkipsEmptyTableName() {
        let plan = TableExport.databasePlan(
            [.init(kind: .table, name: "   ", schema: "public")],
            format: .csv
        )
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.skipped.count, 1)
        XCTAssertEqual(plan.skipped.first?.kind, .table)
    }

    /// 同一 schema 里净化后撞名 ⇒ 顺延，走与整表导出**同一条**算法。
    func testDatabasePlanSuffixesCollisionsWithinSchema() {
        let plan = TableExport.databasePlan(
            [
                .init(kind: .table, name: "a/b", schema: "public"),
                .init(kind: .table, name: "a:b", schema: "public"),
            ],
            format: .csv
        )
        XCTAssertEqual(plan.jobs.map(\.fileName), ["a_b.csv", "a_b-2.csv"])
    }

    /// 空清单不许被当成「导出成功」：`isEmpty` 必须为真，界面据此说「这里没有可导出的表」。
    func testDatabasePlanEmptyWhenNoCandidates() {
        let plan = TableExport.databasePlan([], format: .csv)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.skippedCount, 0)
        XCTAssertFalse(plan.multiSchema)
    }

    // MARK: - 账

    private func labels(orderNote: String = "顺序说明") -> TableExport.Labels {
        TableExport.Labels(
            row: { table, rows, path in "\(table):\(rows):\(path)" },
            failedRow: { table, reason in "\(table):失败:\(reason)" },
            summary: { ok, failed, rows in "汇总:\(ok)/\(failed)/\(rows)" },
            orderNote: orderNote
        )
    }

    func testLedgerSeparatesSuccessAndFailure() {
        var ledger = TableExport.Ledger()
        ledger.record(.succeeded(table: "orders", rows: 42, path: "/tmp/orders.csv"))
        ledger.record(.failed(table: "users", reason: "连接断了"))
        // 取到 30 行之后写盘失败：这一行**有**行数读数，但它不是「导出了 30 行」——
        // 汇总里的行数只算写成的那些表，否则一份失败的文件会替自己报出一批假成果。
        ledger.record(TableExport.Receipt(table: "partial", rows: 30, path: nil, failure: "写到一半失败"))
        XCTAssertEqual(ledger.succeededCount, 1)
        XCTAssertEqual(ledger.failedCount, 2)
        // 失败那张表的行数**不许**并进总数：它本来就没有可交付的成果。
        XCTAssertEqual(ledger.succeededRows, 42)
        XCTAssertFalse(ledger.isEmpty)
    }

    func testLedgerReportListsRowsPathsAndSummary() {
        var ledger = TableExport.Ledger()
        ledger.record(.succeeded(table: "orders", rows: 42, path: "/tmp/orders.csv"))
        ledger.record(.failed(table: "users", reason: "连接断了"))
        let text = ledger.report(labels: labels())
        XCTAssertTrue(text.contains("orders:42:/tmp/orders.csv"), text)
        XCTAssertTrue(text.contains("users:失败:连接断了"), text)
        XCTAssertTrue(text.contains("汇总:1/1/42"), text)
        XCTAssertTrue(text.contains("顺序说明"), text)
    }

    func testLedgerReportOmitsOrderNoteWhenGuaranteed() {
        var ledger = TableExport.Ledger()
        ledger.record(.succeeded(table: "orders", rows: 1, path: "/tmp/orders.csv"))
        XCTAssertFalse(ledger.report(labels: labels(), orderGuaranteed: true).contains("顺序说明"))
        XCTAssertTrue(ledger.report(labels: labels(), orderGuaranteed: false).contains("顺序说明"))
    }

    func testReceiptSuccessRequiresBothPathAndNoFailure() {
        XCTAssertTrue(TableExport.Receipt.succeeded(table: "a", rows: 0, path: "/tmp/a.csv").isSuccess)
        // 有路径但也带了失败原因 ⇒ 不算成功（半个文件不许冒充成品）。
        XCTAssertFalse(
            TableExport.Receipt(table: "a", rows: 0, path: "/tmp/a.csv", failure: "写到一半失败").isSuccess
        )
        XCTAssertFalse(TableExport.Receipt.failed(table: "a", reason: "x").isSuccess)
    }
}
