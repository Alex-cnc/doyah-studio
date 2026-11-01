import AppKit
import SwiftUI
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「数据编辑与表结构」五条的**界面链**探针 —— B6 批次。
///
/// 条目：`FR-STD-DB-DATA-002`（条件计数）· `DATA-005`（单元格 / 单行详情）·
/// `DATA-006`（外键引用导航）· `DDL-003`（表结构编辑器）· `DDL-004`（Schema 对比）。
///
/// ## 这五条为什么一直停在 🟡
///
/// 台账备注原文是「界面呈现 / 点击待人工点验」。核盘之后要分开说：
///   · 「count 语句怎么拼、JSON 怎么判、外键怎么解析、ALTER 怎么排、差异怎么算」早有单测
///     （`RowBrowsingQueryTests` / `CellInspectorTests` / `ForeignKeyNavigationTests` /
///      `TableDesignTests` / `TableDesignChangeSetTests` / `SchemaDiffTests`）；
///   · 缺的是**中间那一段**：从这里按下去（`countRows` / `jumpToReferencedRow` /
///     `alterTable` / `schemaDiffPlan`）到「哪几条语句真的发出去、发到哪个库、顺序如何」。
///     那一段可以少发一条、可以把 WHERE 丢掉、可以把 DROP 也塞进默认脚本、
///     可以在没预览时也执行 —— 上面那些用例照样全绿。
///
/// ## 怎么量（本机没有稳定在跑的实例，探针不依赖它）
///
/// 与本批前几跳同一处注入缝（`AppState.serviceOverride`）：假 `DatabaseService` 记下收到的
/// **每一条**语句，按 SQL 内容回结果集。另有两处**结构性**判定：
///   · `FR-DATA-006` 的入口可见性只在 Core 一处判（`ForeignKeyNavigation.entryVisible`），
///     本文件判规则 + `AppState` 的元数据缓存，视图那一行由源锚点钉住；
///   · `DDL-003` 的「不许猜列类型」判在生成层：类型为空必须**整批拒绝**，不是少一条。
///
/// ## 边界（如实登记，别把这条读成「人点过了」）
///
/// · **不是真数据库**：真库返回的元数据（权限过滤、`information_schema` 细节）不在本文件；
///   217 本跳仍连不通 ⇒ 真库读数 0 次，记「未知」。
/// · **真鼠标**：右键那一击由合成 `NSEvent` 走 `menu(for:)`（AppKit 自己算 `clickedRow`），
///   但「屏幕上弹出来长什么样」归快照层。
/// · **模态 / 保存面板**一律不弹（无人值守弹出来就回不来），本文件不碰。
final class TableEditDDLProbeTests: XCTestCase {

    // MARK: - 脚本化假服务

    final class ScriptedService: DatabaseService, @unchecked Sendable {
        let config: ConnectionConfig

        private let lock = NSLock()
        private var recorded: [String] = []
        private let router: (String) -> QueryResult?

        init(config: ConnectionConfig, router: @escaping (String) -> QueryResult?) {
            self.config = config
            self.router = router
        }

        var statements: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func connect() async throws -> ServerInfo {
            ServerInfo(version: "18.6", database: config.database, user: config.username)
        }

        func disconnect() async {}
        func beginTransaction() async throws {}
        func commit() async throws {}
        func rollback() async throws {}
        func cancel(_ handle: ExecutionHandle) async -> CancelOutcome { .notActive }
        func ownSessionPID() async -> Int? { nil }

        func execute(
            _ sql: String,
            options: QueryOptions,
            handle: ExecutionHandle
        ) -> AsyncThrowingStream<QueryEvent, Error> {
            lock.lock()
            recorded.append(sql)
            lock.unlock()
            let result = router(sql)
            return AsyncThrowingStream { continuation in
                continuation.yield(.started(statementIndex: 0))
                if let result { continuation.yield(.resultSet(result)) }
                continuation.yield(.finished(QuerySummary(statementCount: 1, duration: 0)))
                continuation.finish()
            }
        }
    }

    // MARK: - 夹具

    private static func pinEgressDirectoryIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        if let injected = environment["DOYAH_EGRESS_LOG_DIR"], !injected.isEmpty { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fallback = root.appendingPathComponent(".build/ui-probe-egress", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        setenv("DOYAH_EGRESS_LOG_DIR", fallback.path, 1)
    }

    @MainActor
    private func makeState(dbType: DatabaseType = .postgresql) async -> (AppState, ConnectionConfig) {
        Self.pinEgressDirectoryIfNeeded()
        let config = ConnectionConfig(
            name: "探针库",
            dbType: dbType,
            host: "127.0.0.1",
            port: 5432,
            database: "shop",
            username: "probe"
        )
        let state = AppState()
        await state.startupChain?.value
        state.connections = [config]
        state.selectedConnectionID = config.id
        return (state, config)
    }

    private func result(_ columns: [String], _ rows: [[String?]]) -> QueryResult {
        QueryResult(
            columns: columns.enumerated().map { ColumnMeta(id: $0.offset, name: $0.element) },
            rows: rows
        )
    }

    private func ordersTable() -> DatabaseObject {
        DatabaseObject(id: "table:public.orders", name: "orders", kind: .table, database: "shop", schema: "public")
    }

    private func ordersRef() -> DatabaseObjectRef {
        DatabaseObjectRef(schema: "public", name: "orders")
    }

    /// 轮询等待（异步任务里的执行链落不了地时不要死等）。
    @MainActor
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    // MARK: - ① FR-STD-DB-DATA-002：条件计数

    /// 「统计行数」按下去只发**一条** `count(*)`，带的 WHERE 与预览一致，并进新页签执行。
    @MainActor
    func testCountEntrySendsOneCountStatementAndOpensItInATab() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            sql.contains("count(*)") ? self.result(["count"], [["3"]]) : nil
        }
        state.serviceOverride = service

        var filter = RowBrowsingQuery.Filter()
        filter.whereClause = "status = 'paid'"
        filter.orderBy = "created_at desc"
        state.countRows(ordersTable(), filter: filter)

        let arrived = await waitUntil { !service.statements.isEmpty }
        XCTAssertTrue(arrived, "点了「统计行数」之后一条语句都没发出去")

        let statements = service.statements
        XCTAssertEqual(statements.count, 1, "计数只许发一条（不是浏览 + 计数两条）：\(statements)")
        XCTAssertEqual(statements[0], #"SELECT count(*) FROM "public"."orders" WHERE status = 'paid';"#,
                       "计数语句带了不该带的东西（ORDER BY 对计数无意义）：\(statements[0])")

        let tab = try XCTUnwrap(state.tabs.last)
        XCTAssertEqual(tab.sql, statements[0], "页签里的语句与发出去的不是同一条")
        // 计数结果没有来源表（它只有一列 count，内联编辑 / 复制为 INSERT 对它没有意义）——
        // 这一条**不**要求 sourceTable，只要求语句与预览一致。
        XCTAssertNil(tab.sourceTable, "计数结果被标成了可编辑的来源表")
        print("🧪 计数：\(statements[0])")
    }

    /// 条件里塞第二条语句 ⇒ 拒绝、**一条都不发**（不是"尽力执行前半句"）。
    @MainActor
    func testCountRefusesMultiStatementAndSendsNothing() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { _ in self.result(["count"], [["0"]]) }
        state.serviceOverride = service

        var filter = RowBrowsingQuery.Filter()
        filter.whereClause = "id = 1; DROP TABLE orders"
        let tabsBefore = state.tabs.count
        state.countRows(ordersTable(), filter: filter)

        XCTAssertTrue(service.statements.isEmpty, "多语句条件被发了出去：\(service.statements)")
        XCTAssertEqual(state.tabs.count, tabsBefore, "被拒的计数还开了新页签")
        XCTAssertNotNil(state.errorMessage, "被拒了却没有任何提示")
    }

    // MARK: - ② FR-STD-DB-DATA-005：单元格 / 单行详情

    /// 行详情侧栏的**取值模型**：列序不漂、JSON 竖排、NULL 与空串分得开、长值报原文长度。
    ///
    /// 侧栏本身只排版（`RowDetailPanel` 不判定类型），所以判在 `CellInspector.row` 这一层；
    /// 「侧栏拿到的是用户选中那一行（含分页偏移）」由 `ResultTableView.selectedDetailRow` 这一处源锚点钉住。
    @MainActor
    func testRowDetailPanelModelKeepsOrderAndFormatsLongJSON() throws {
        let columns = [
            ColumnMeta(id: 0, name: "id", typeName: "int4"),
            ColumnMeta(id: 1, name: "payload", typeName: "jsonb"),
            ColumnMeta(id: 2, name: "note", typeName: "text"),
            ColumnMeta(id: 3, name: "blob", typeName: "bytea"),
        ]
        let json = #"{"order":42,"items":[{"sku":"A-1","qty":2}],"memo":"长文本"}"#
        let fields = CellInspector.row(columns: columns, row: ["7", json, "", nil])

        XCTAssertEqual(fields.map(\.columnName), ["id", "payload", "note", "blob"], "字段顺序不是列顺序")
        XCTAssertEqual(fields[1].value.shape, .jsonObject)
        XCTAssertTrue(fields[1].value.display.contains("\n"), "JSON 没有竖排展开：\(fields[1].value.display)")
        XCTAssertTrue(fields[1].value.display.contains("\"sku\" : \"A-1\"")
                      || fields[1].value.display.contains("\"sku\": \"A-1\""),
                      "JSON 美化结果里认不出原始键值：\(fields[1].value.display)")
        XCTAssertEqual(fields[2].value.shape, .empty, "空串被当成了 NULL")
        XCTAssertEqual(fields[1].value.display.contains("null"), false, "空串被写成了字面量 null")
        XCTAssertEqual(fields[3].value.shape, .null, "真 NULL 没有单独一档")

        // 长值：截断必须把**原始长度**一起说出来。
        let long = String(repeating: "值", count: 5_000)
        let huge = CellInspector.inspect(long)
        XCTAssertTrue(huge.isTruncated, "5000 字符没有被截断（界面会卡）")
        XCTAssertEqual(huge.originalCharacterCount, 5_000)
        XCTAssertTrue(
            huge.summary().contains("5000") || huge.summary().contains("5,000"),
            "摘要没报原始长度：\(huge.summary())"
        )
        print("🧪 行详情模型：\(fields.map { $0.value.summary() }.joined(separator: " | "))")
    }

    // MARK: - ③ FR-STD-DB-DATA-006：外键引用导航

    /// 元数据没读到 ⇒ 入口不露；读到了 ⇒ 只有**真挂着外键**的那一列露。
    @MainActor
    func testJumpEntryNeedsForeignKeyMetadataBeforeItIsShown() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            if sql.contains("pg_constraint") || sql.contains("information_schema.table_constraints") {
                return self.result(
                    ["conname", "contype", "def"],
                    [["orders_customer_fk", "f", "FOREIGN KEY (customer_id) REFERENCES customers(id)"]]
                )
            }
            return nil
        }
        state.serviceOverride = service
        let orders = ordersTable()

        // 还没读 ⇒ nil ⇒ 入口不露（旧行为是常驻，点下去才说"没有外键"）。
        XCTAssertNil(state.jumpableColumns(for: ordersRef()), "元数据没读就把入口放出来了")
        XCTAssertFalse(ForeignKeyNavigation.entryVisible(jumpable: nil, clickedColumn: "customer_id"))

        await state.ensureForeignKeyColumns(for: ordersRef())

        let columns = try XCTUnwrap(state.jumpableColumns(for: ordersRef()), "读了元数据却没有缓存")
        XCTAssertEqual(columns, ["customer_id"], "有外键的列集不对：\(columns)")
        XCTAssertTrue(ForeignKeyNavigation.entryVisible(jumpable: columns, clickedColumn: "customer_id"))
        XCTAssertFalse(ForeignKeyNavigation.entryVisible(jumpable: columns, clickedColumn: "note"),
                       "没有外键的列也露出了入口")
        XCTAssertNil(state.jumpableColumns(for: nil), "手写 SQL 的结果（没有来源表）也给了入口")
        print("🧪 可跳列：\(columns.sorted())")
    }

    /// 点「跳到被引用行」⇒ 新页签里是**目标表 + 值已带入**的查询，并立刻执行。
    @MainActor
    func testJumpOpensTheReferencedTableWithTheValueBakedIn() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            // 顺序要紧：结构查询里也含 `information_schema.table_constraints`（主键子查询），
            // 先判结构，否则会把约束行当成列定义读进去（本跳第一版就这么错过）。
            if sql.contains("c.column_name") {
                // 源表结构：customer_id 是整数列 ⇒ 值不加引号。
                return self.result(
                    ["column_name", "data_type", "is_nullable", "column_default", "is_primary_key"],
                    [["customer_id", "integer", "YES", nil, "NO"]]
                )
            }
            if sql.contains("pg_constraint") || sql.contains("table_constraints") {
                return self.result(
                    ["conname", "contype", "def"],
                    [["orders_customer_fk", "f", "FOREIGN KEY (customer_id) REFERENCES customers(id)"]]
                )
            }
            if sql.contains("SELECT * FROM") {
                return self.result(["id", "name"], [["42", "Ada"]])
            }
            return nil
        }
        state.serviceOverride = service

        var tab = QueryTab(title: "浏览 orders", sql: "SELECT * FROM orders", connectionID: config.id, database: "shop")
        tab.sourceTable = DatabaseObjectRef(schema: "public", name: "orders")
        state.tabs.append(tab)
        state.selectedTabID = tab.id

        state.jumpToReferencedRow(column: "customer_id", value: "42")

        let arrived = await waitUntil {
            state.tabs.last?.sql.contains("customers") == true && !service.statements.isEmpty
        }
        XCTAssertTrue(arrived, "点了跳转之后没有新页签")
        let sql = try XCTUnwrap(state.tabs.last?.sql)
        XCTAssertEqual(sql, #"SELECT * FROM "public"."customers" WHERE "id" = 42 LIMIT 200;"#)
        XCTAssertTrue(service.statements.contains(sql), "跳转语句没有真的执行：\(service.statements)")
        print("🧪 外键跳转：\(sql)")
    }

    /// 没有外键 ⇒ 直说，且**不生成一条必然查不到的语句**。
    @MainActor
    func testJumpWithoutForeignKeySaysSoAndOpensNothing() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            sql.contains("pg_constraint") || sql.contains("table_constraints")
                ? self.result(["conname", "contype", "def"], [["orders_note_check", "c", "CHECK (note <> '')"]])
                : nil
        }
        state.serviceOverride = service

        var tab = QueryTab(title: "浏览 orders", sql: "SELECT * FROM orders", connectionID: config.id, database: "shop")
        tab.sourceTable = DatabaseObjectRef(schema: "public", name: "orders")
        state.tabs.append(tab)
        state.selectedTabID = tab.id

        let tabsBefore = state.tabs.count
        state.jumpToReferencedRow(column: "note", value: "hello")
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(state.tabs.count, tabsBefore, "没有外键却开了一个新页签")
        let message = state.statusMessage
        XCTAssertTrue(
            message.contains("外键") || message.lowercased().contains("foreign key"),
            "没有一句「这一列没有外键」：\(message)"
        )
        XCTAssertFalse(service.statements.contains { $0.hasPrefix("SELECT * FROM") },
                       "没有外键还是发了一条查询：\(service.statements)")
    }

    // MARK: - ④ FR-STD-DB-DDL-003：表结构编辑器

    /// 新增列**不带默认类型**：空类型会被校验报出来，提交变灰；生成层整批拒绝（不猜 `text`）。
    @MainActor
    func testDesignSheetStartsNewColumnsWithoutAGuessedType() {
        var fresh = TableDesign.blankColumn()
        fresh.name = "amount"
        XCTAssertEqual(fresh.typeName, "", "新列的默认类型被预填成了 \(fresh.typeName)（那是替使用者猜）")

        let issues = TableDesign.validate(
            tableName: "orders",
            columns: [
                TableColumnDefinition(name: "id", typeName: "bigint", isNullable: false, isPrimaryKey: true),
                fresh,
            ]
        )
        XCTAssertTrue(issues.contains { issue in
            if case .columnTypeEmpty(let name) = issue { return name == "amount" }
            return false
        }, "空类型没有被校验报出来 —— 提交按钮就不会变灰：\(issues)")

        let pg = PostgresDialect()
        XCTAssertTrue(
            TableDesignChangeSet.createTablePlan(
                table: "orders",
                columns: [TableColumnDefinition(name: "id", typeName: "bigint"), fresh],
                schema: "public",
                extras: nil,
                dialect: pg
            ).isEmpty,
            "类型为空时仍生成了建表计划（替人猜了一个类型）"
        )
        XCTAssertTrue(
            TableDesignChangeSet.statements(
                for: TableDesignChangeSet(
                    originalColumns: [TableColumnDefinition(name: "note", typeName: "text")],
                    editedColumns: [TableColumnDefinition(name: "note")]
                ),
                table: "orders",
                schema: "public",
                dialect: pg
            ).isEmpty,
            "类型被清空时仍生成了 ALTER（会发出一条 `TYPE ;`）"
        )
    }

    /// 表结构变更：**先预览、再执行**，且四条语句按固定顺序发出去。
    @MainActor
    func testAlterPlanRunsOnlyAfterItsPreviewAndInTheFixedOrder() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { _ in self.result(["ok"], [["1"]]) }
        state.serviceOverride = service

        let pg = PostgresDialect()
        let original = [
            TableColumnDefinition(name: "id", typeName: "bigint", isNullable: false, isPrimaryKey: true),
            TableColumnDefinition(name: "note", typeName: "text"),
        ]
        let edited = [
            original[0],
            TableColumnDefinition(name: "note", typeName: "text"),
            TableColumnDefinition(name: "amount", typeName: "numeric(10,2)"),
        ]
        let changeSet = TableDesignChangeSet(
            originalColumns: original,
            editedColumns: edited,
            newIndexes: [SQLGenerator.IndexDefinition(name: "orders_amount_idx", table: "orders", schema: "public", columns: ["amount"])],
            droppedIndexes: ["orders_note_idx"],
            droppedConstraints: ["orders_note_check"]
        )
        let expected = TableDesignChangeSet.statements(
            for: changeSet,
            table: "orders",
            schema: "public",
            dialect: pg
        )
        XCTAssertEqual(expected.count, 4, "计划条数不对：\(expected)")

        // ① 没有预览 ⇒ 一条都不发。
        let refused = await state.alterTable(ordersTable(), changeSet: changeSet)
        XCTAssertFalse(refused, "没预览也执行了")
        XCTAssertTrue(service.statements.isEmpty, "被拒的那次仍发了语句：\(service.statements)")
        XCTAssertNotNil(state.errorMessage)

        // ② 预览（面板把同一份脚本交上来）⇒ 按预览那份顺序执行。
        state.recordDDLPreview(expected.joined(separator: "\n"))
        let applied = await state.alterTable(ordersTable(), changeSet: changeSet)
        XCTAssertTrue(applied, "预览过了却没执行：\(state.errorMessage ?? "无提示")")
        XCTAssertEqual(service.statements, expected, "真正发出去的语句与预览不是同一份 / 顺序不对")

        XCTAssertTrue(service.statements[0].contains("DROP CONSTRAINT"), service.statements[0])
        XCTAssertTrue(service.statements[1].contains("DROP INDEX"), service.statements[1])
        XCTAssertTrue(service.statements[2].contains("ADD COLUMN"), service.statements[2])
        XCTAssertTrue(service.statements[3].contains("CREATE INDEX"), service.statements[3])
        print("🧪 表结构变更：\(service.statements.count) 条，顺序 \(service.statements.map { $0.split(separator: " ").prefix(3).joined(separator: " ") })")
    }

    // MARK: - ⑤ FR-STD-DB-DDL-004：Schema 对比与同步

    /// 两侧各抓一张快照 → 只把"期望有、目标缺 / 不一致"的部分写成脚本；
    /// 目标库多出来的表**默认不动**（要删得显式开 allowDrop），且被跳过的要如实列出来。
    @MainActor
    func testSchemaDiffScriptsOnlyTickedChangesAndNeverDropsByDefault() async throws {
        let (state, config) = await makeState()
        var listCall = 0
        let lock = NSLock()

        let service = ScriptedService(config: config) { sql in
            if sql.contains("information_schema.tables") {
                lock.lock()
                listCall += 1
                let call = listCall
                lock.unlock()
                // 第 1 / 3 次 = 期望结构（源），第 2 / 4 次 = 目标库。
                let names = call % 2 == 1 ? ["orders", "users"] : ["legacy", "users"]
                return QueryResult(
                    columns: [ColumnMeta(id: 0, name: "table_name"), ColumnMeta(id: 1, name: "table_type")],
                    rows: names.map { [$0, "BASE TABLE"] }
                )
            }
            if sql.contains("column_name") {
                if sql.contains("'orders'") {
                    return self.result(
                        ["column_name", "data_type", "is_nullable", "column_default", "is_primary_key"],
                        [["id", "bigint", "NO", nil, "YES"], ["note", "text", "YES", nil, "NO"]]
                    )
                }
                if sql.contains("'legacy'") {
                    return self.result(
                        ["column_name", "data_type", "is_nullable", "column_default", "is_primary_key"],
                        [["id", "bigint", "NO", nil, "YES"]]
                    )
                }
                return self.result(
                    ["column_name", "data_type", "is_nullable", "column_default", "is_primary_key"],
                    [["id", "bigint", "NO", nil, "YES"]]
                )
            }
            return nil
        }
        state.serviceOverride = service

        let second = ConnectionConfig(
            name: "目标库",
            dbType: .postgresql,
            host: "127.0.0.1",
            port: 5433,
            database: "shop_copy",
            username: "probe"
        )
        state.connections.append(second)

        let safe = try await state.schemaDiffPlan(
            sourceConnectionID: config.id,
            sourceDatabase: "shop",
            targetConnectionID: second.id,
            targetDatabase: "shop_copy",
            schema: "public",
            allowsDrop: false
        )
        XCTAssertFalse(safe.isIdentical, "两侧结构不同却报「完全一致」")
        XCTAssertTrue(safe.statements.contains { $0.contains("CREATE TABLE") && $0.contains("orders") },
                      "目标库缺 orders 却没生成建表：\(safe.statements)")
        XCTAssertFalse(safe.statements.contains { $0.uppercased().contains("DROP TABLE") },
                       "默认脚本里出现了 DROP TABLE：\(safe.statements)")
        XCTAssertTrue(safe.skippedDestructive.contains { $0.contains("legacy") },
                      "被跳过的删除没有如实列出来：\(safe.skippedDestructive)")

        let destructive = try await state.schemaDiffPlan(
            sourceConnectionID: config.id,
            sourceDatabase: "shop",
            targetConnectionID: second.id,
            targetDatabase: "shop_copy",
            schema: "public",
            allowsDrop: true
        )
        XCTAssertTrue(destructive.statements.contains { $0.uppercased().contains("DROP TABLE") && $0.contains("legacy") },
                      "显式开了 allowDrop 仍没有删表：\(destructive.statements)")
        print("🧪 Schema 对比：默认 \(safe.statements.count) 条 / 跳过 \(safe.skippedDestructive.count) 条；允许删除 \(destructive.statements.count) 条")
    }
}
