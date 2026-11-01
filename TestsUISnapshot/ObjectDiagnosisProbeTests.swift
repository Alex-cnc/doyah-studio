import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 连接上下文里的诊断入口（`FR-STD-DB-DIAG-006`）的**界面链**探针 —— B5 批次最后一条。
///
/// ## 这条为什么一直停在 ⬜
///
/// 台账目标列在此之前一直是 `—`（需求书 §3.4 有原文，台账没落定义），而判据三条全是
/// 「点下去之后」才成立的：① 从对象树右键唤起且上下文自动带入；② 结论里的对象名可点、跳到对应节点；
/// ③ 没有统计读数时明说「未取到」，不编。
///
/// ## 怎么量（本机没有稳定在跑的实例，探针不依赖它）
///
/// 与前一批同一处注入缝（`AppState.serviceOverride`）：假 `DatabaseService` 记下收到的每一条语句，
/// 按 SQL 内容回结果集 —— 判的是「从右键唤起之后，取证到底发了哪几条、读数从哪儿来、
/// 结论里的名字点了之后请求了什么」。
///
/// ## 边界（如实登记，别把这条读成「人点过了」）
///
/// · **不是真数据库**：`pg_stat_user_tables` 等视图真库返回的行（类型、权限过滤、统计延迟）
///   不在本文件；217（`192.168.5.217:5432`）本跳仍连不通 ⇒ 真库读数 0 次，记「未知」。
/// · **真鼠标点一下链接**由人承担：本文件判的是「那句话里的名字确实带上了链接属性、
///   解码出来的身份正确、按这条身份发出的跳转请求正确」。
/// · **树的展开与选中**是视图内部状态（`ObjectTreeView.expandedIDs`），本文件判的是
///   「发出的请求里是什么」；展开后画得对不对归快照层。
final class ObjectDiagnosisProbeTests: XCTestCase {

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

    /// 对象树里那一行（表 `public.orders`）。
    private func ordersTable(database: String = "shop") -> DatabaseObject {
        DatabaseObject(
            id: "table:public.orders",
            name: "orders",
            kind: .table,
            database: database,
            schema: "public"
        )
    }

    /// 一跑成功回执（读数：耗时 12 ms、返回 3 行、影响 2 行）。
    private func receipt(
        sql: String = "select * from orders where id > 10",
        outcome: ExecutionOutcome = .succeeded,
        affectedRows: Int? = 2,
        rowCount: Int = 3
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            executedAt: Date(timeIntervalSince1970: 1_800_000_000),
            duration: 0.012,
            connectionName: "探针库",
            database: "shop",
            scopeTitle: "整篇",
            statementCount: 1,
            outcome: outcome,
            affectedRows: affectedRows,
            results: ExecutionReceipt.ResultReading(resultSetCount: 1, rowCount: rowCount, columnCount: 4),
            sql: sql
        )
    }

    @MainActor
    private func addTab(to state: AppState, config: ConnectionConfig, receipt: ExecutionReceipt?) -> QueryTab {
        var tab = QueryTab(title: "查询 1", sql: "select 1", connectionID: config.id, database: "shop")
        if let receipt { tab.receiptLog.append(receipt) }
        state.tabs.append(tab)
        state.selectedTabID = tab.id
        return tab
    }

    // MARK: - ① 作用域：连接 / 库 / 对象 / 最近一次执行的读数

    @MainActor
    func testScopeCarriesConnectionDatabaseObjectAndLastExecutionReadings() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: receipt())
        let object = ordersTable()

        state.beginObjectDiagnosis(for: object)

        let scope = try XCTUnwrap(state.objectDiagnosisScope, "从对象树唤起之后没有作用域")
        XCTAssertEqual(scope.objectKind, .table)
        XCTAssertEqual(scope.objectName, "orders")
        XCTAssertEqual(scope.schema, "public")
        XCTAssertEqual(scope.database, "shop", "库没带进上下文")
        XCTAssertTrue(scope.connectionLabel.contains("probe"), "连接没带进上下文：\(scope.connectionLabel)")
        XCTAssertFalse(scope.connectionLabel.lowercased().contains("password"), "上下文里出现了口令字段")

        let reading = try XCTUnwrap(scope.lastExecution, "最近一次执行的读数没带进来")
        XCTAssertEqual(reading.durationMilliseconds, 12)
        XCTAssertEqual(reading.rowCount, 3)
        XCTAssertEqual(reading.affectedRows, 2)
        XCTAssertEqual(reading.outcome, .succeeded)
        XCTAssertEqual(reading.statement, "select * from orders where id > 10")

        // 面板真的开了，而且问题里点的是这个对象（不是页签里那条 `select 1`）。
        XCTAssertTrue(state.isDiagnosisPresented, "面板没打开")
        XCTAssertTrue(state.diagnosisQuestion.contains("public.orders"),
                      "问题里没点名被诊断的对象：\(state.diagnosisQuestion)")
        XCTAssertEqual(state.diagnosisTargetSQL, "SELECT * FROM \"public\".\"orders\" LIMIT 200 OFFSET 0;",
                       "诊断语句没按对象给：\(state.diagnosisTargetSQL)")
        print("🧪 作用域读数：\(scope.summary(language: .simplifiedChinese)) · \(reading.readingLine(language: .simplifiedChinese))")
    }

    // MARK: - ③ 没有读数 = 未取到（不是 0 行 0 ms）

    @MainActor
    func testRefusedOrMissingReceiptReadsAsNotAvailableInsteadOfZero() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: nil)
        state.beginObjectDiagnosis(for: ordersTable())

        let scope = try XCTUnwrap(state.objectDiagnosisScope)
        XCTAssertNil(scope.lastExecution, "一次都没执行过，却造出了一跑读数")

        // 被拒的那一跑也算「没执行过」：它一条语句都没发出去，读数不是它的。
        let refused = receipt(sql: "update orders set note = 'x'", outcome: .refused, affectedRows: nil, rowCount: 0)
        XCTAssertNil(DiagnosisScope.LastExecution(receipt: refused),
                     "「被拒绝」的那一跑被当成了执行读数（会写出 0 行 0 ms）")

        let plan = scope.plannedEvidence(
            dialect: SQLDialectFactory.make(for: .postgresql),
            language: .simplifiedChinese
        )
        let item = try XCTUnwrap(plan.first(where: { $0.kind == .lastExecution }))
        XCTAssertNil(item.sql, "没有读数却给了 SQL")
        let reason = try XCTUnwrap(item.unavailableReason)
        XCTAssertTrue(reason.contains("未取到"), "没读到「未取到」：\(reason)")
    }

    // MARK: - ①+③ 表：逐条取证、统计按对象收窄、读数进证据

    @MainActor
    func testTableScopeGathersScopedStatisticsAndTheLastReadingInOrder() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: receipt())
        state.beginObjectDiagnosis(for: ordersTable())

        let service = ScriptedService(config: config) { sql in
            if sql.hasPrefix("EXPLAIN") {
                return self.result(["QUERY PLAN"], [["Seq Scan on orders  (cost=0.00..18.50 rows=3 width=64)"]])
            }
            if sql.contains("pg_stat_user_tables") {
                return self.result(
                    ["schemaname", "relname", "seq_scan", "idx_scan", "n_live_tup", "bytes"],
                    [["public", "orders", "42", "0", "3", "8192"]]
                )
            }
            return nil
        }
        state.serviceOverride = service

        await state.gatherDiagnosisEvidence(sql: state.diagnosisTargetSQL)

        XCTAssertEqual(state.diagnosisEvidence.map(\.kind),
                       [.statement, .executionPlan, .objectStats, .lastExecution],
                       "证据清单不是「语句 → 计划 → 对象统计 → 最近一次执行」：\(state.diagnosisEvidence.map(\.kind))")

        let statements = service.statements
        XCTAssertEqual(statements.count, 2, "取证发了 \(statements.count) 条语句（应当只有 EXPLAIN 与统计两条）：\(statements)")
        let stats = try XCTUnwrap(statements.first(where: { $0.contains("pg_stat_user_tables") }))
        XCTAssertTrue(stats.contains("relname = 'orders'"), "统计查询没有按对象收窄：\(stats)")
        XCTAssertTrue(stats.contains("schemaname = 'public'"), "统计查询没有按 schema 收窄：\(stats)")
        XCTAssertFalse(statements.contains(where: { $0.contains("pg_locks") }),
                       "对象诊断里塞了整实例的锁查询（会被读成「这张表在等锁」）")

        let statsEvidence = try XCTUnwrap(state.diagnosisEvidence.first(where: { $0.kind == .objectStats }))
        XCTAssertTrue(statsEvidence.isAvailable, "统计取到了却记成取不到")
        XCTAssertEqual(statsEvidence.rows.first, ["public", "orders", "42", "0", "3", "8192"])

        let readingEvidence = try XCTUnwrap(state.diagnosisEvidence.first(where: { $0.kind == .lastExecution }))
        XCTAssertTrue(readingEvidence.isAvailable)
        XCTAssertEqual(readingEvidence.rows.count, 1)
        XCTAssertEqual(readingEvidence.rows[0].first, "select * from orders where id > 10")
        print("🧪 表作用域取证：\(statements.count) 条语句 · 证据 \(state.diagnosisEvidence.map(\.kind))")
    }

    // MARK: - ③ 没有统计视图的对象：明说未取到、一条语句都不发

    @MainActor
    func testObjectWithoutStatisticsSaysNotAvailableAndSendsNoQuery() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: nil)

        // 列：没有独立的统计视图 —— 一条语句都不许发，也不许给一张空表。
        let column = DatabaseObject(id: "column:public.orders.id", name: "id", kind: .column, database: "shop", schema: "public")
        state.beginObjectDiagnosis(for: column)
        let service = ScriptedService(config: config) { _ in nil }
        state.serviceOverride = service
        await state.gatherDiagnosisEvidence(sql: "")

        XCTAssertEqual(service.statements, [], "列上没有统计视图，却发了语句：\(service.statements)")
        let columnStats = try XCTUnwrap(state.diagnosisEvidence.first(where: { $0.kind == .objectStats }))
        XCTAssertFalse(columnStats.isAvailable, "列没有统计视图，却记成「取到了」")
        // 证据的措辞跟着**界面语言**走（这里不写死中文，否则英文环境上判红的是翻译而不是行为）；
        // 「为什么取不到」那段原因必须出现在 note 里（判据 ③：明说，不含糊）。
        let language = LocalizationManager.shared.effectiveLanguage
        XCTAssertTrue(
            columnStats.note.contains(LocalizedStrings.text(.diagnosisStatsColumn, language: language)),
            "note 里没有「为什么取不到」：\(columnStats.note)"
        )
        XCTAssertEqual(columnStats.rows, [], "取不到却塞了行（空表会被读成「没扫过」）")
        XCTAssertTrue(state.diagnosisLinkTargets.isEmpty, "列节点不该给出可点的对象名（没有父表身份）")

        // 视图：开销记在底层表上，也不许编。
        let view = DatabaseObject(id: "view:public.order_totals", name: "order_totals", kind: .view, database: "shop", schema: "public")
        let pg = SQLDialectFactory.make(for: .postgresql)
        let viewScope = DiagnosisScope(object: view, connectionLabel: "probe@127.0.0.1:5432", database: "shop", lastExecution: nil)
        XCTAssertNil(viewScope.statisticsQuery(dialect: pg), "视图被给了自己的统计查询")
        XCTAssertTrue(
            (viewScope.statisticsUnavailableReason(language: .simplifiedChinese, dialect: pg) ?? "").contains("未取到"),
            "视图上没读到「未取到」"
        )

        // 非 PG 方言：这几个视图不存在 —— 也不许发 PG 口径的查询。
        let mysql = SQLDialectFactory.make(for: .mysql)
        XCTAssertNil(DiagnosisScope(object: ordersTable(), connectionLabel: "p", database: "shop", lastExecution: nil)
            .statisticsQuery(dialect: mysql), "MySQL 上给了 PG 统计视图的查询")
        XCTAssertTrue(
            (DiagnosisScope(object: ordersTable(), connectionLabel: "p", database: "shop", lastExecution: nil)
                .statisticsUnavailableReason(language: .simplifiedChinese, dialect: mysql) ?? "").contains("未取到"),
            "非 PG 方言上没读到「未取到」"
        )
    }

    // MARK: - ① 右键入口：两套渲染都在，点下去上下文自动带入

    @MainActor
    func testDiagnoseEntryIsInBothRenderingsAndCarriesTheContext() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: receipt())
        // 让「已连接」成立（菜单项在未连接时是灰的）—— 走的是与产品同一条 `ensureService`。
        let service = ScriptedService(config: config) { _ in nil }
        state.serviceOverride = service
        _ = try? await state.loadMetadataRoot()

        let object = ordersTable()
        let menu = ObjectTreeAppKitMenu.build(object: object, appState: state, onEdit: nil)
        let title = L(.treeActionDiagnose)
        let item = try XCTUnwrap(menu.items.first(where: { $0.title == title }),
                                 "生产右键菜单里没有「\(title)」：\(menu.items.map(\.title))")
        // 灰 / 亮必须跟着**同一个**连接状态走（探针缝不登记 `services` ⇒ 这里状态是「未连接」，
        // 所以判的是「两者一致」而不是「一定是亮的」；真连接上由 `isObjectTreeConnected` 决定）。
        XCTAssertEqual(item.isEnabled, state.isObjectTreeConnected,
                       "诊断入口的灰 / 亮没有跟着连接状态走")

        // 按菜单项自己的 target/action 派发（用户点它走的就是这条路）。
        let action = try XCTUnwrap(item.action)
        let target = try XCTUnwrap(item.target)
        _ = (target as AnyObject).perform(action, with: item)

        let scope = try XCTUnwrap(state.objectDiagnosisScope, "点了诊断入口，作用域没带进来")
        XCTAssertEqual(scope.objectName, "orders")
        XCTAssertEqual(scope.database, "shop")
        XCTAssertTrue(state.isDiagnosisPresented, "点了诊断入口，面板没打开")

        // 服务器节点（= 「当前连接」那一级）也有同一项。
        let server = DatabaseObject(id: "server:probe", name: "探针库", kind: .server, database: "shop")
        let serverMenu = ObjectTreeAppKitMenu.build(object: server, appState: state, onEdit: nil)
        XCTAssertTrue(serverMenu.items.contains { $0.title == title }, "服务器节点上没有诊断入口")

        // 两套渲染都必须有这一项（第七十批踩过：只加进 SwiftUI 那份，生产右键走的是 AppKit）。
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let swiftUI = try String(contentsOf: root.appendingPathComponent("App/Views/ObjectTreeContextMenu.swift"), encoding: .utf8)
        XCTAssertTrue(swiftUI.contains("L(.treeActionDiagnose)"), "SwiftUI 那份菜单没有诊断项")
        XCTAssertTrue(swiftUI.contains("beginObjectDiagnosis(for: object)"), "SwiftUI 那份菜单没接到同一条收口")
    }

    // MARK: - ② 结论里的对象名：带链接、解得回身份、点了发跳转请求

    @MainActor
    func testClickedObjectNameBecomesALinkAndJumpsToThatNode() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: receipt())
        state.beginObjectDiagnosis(for: ordersTable())

        let conclusion = "public.orders 上顺序扫描了 42 次、索引扫描 0 次，先补一个 (id) 上的索引。[依据: e3]"
        let targets = state.diagnosisLinkTargets
        let attributed = DiagnosisObjectLinker.attributed(conclusion, targets: targets)

        var linked: [(text: String, target: DiagnosisObjectLinker.Target)] = []
        for run in attributed.runs where run.link != nil {
            let text = String(attributed[run.range].characters)
            let target = DiagnosisObjectLinker.Target(url: run.link!)
            linked.append((text, try XCTUnwrap(target, "链接解不回对象身份：\(run.link!)")))
        }

        XCTAssertEqual(linked.count, 1, "结论里的对象名该有 1 处链接，实际 \(linked.count) 处")
        XCTAssertEqual(linked.first?.text, "public.orders", "链接的不是结论里那个限定名")
        let target = try XCTUnwrap(linked.first?.target)
        XCTAssertEqual(target.kind, .table)
        XCTAssertEqual(target.name, "orders")
        XCTAssertEqual(target.schema, "public")

        state.jumpToDiagnosisObject(target)
        let request = try XCTUnwrap(state.treeJumpRequest, "点了对象名没发出跳转请求")
        XCTAssertEqual(request.kind, .table)
        XCTAssertEqual(request.name, "orders")
        XCTAssertEqual(request.schema, "public")
        XCTAssertEqual(request.database, "shop", "跳转请求里没带库")
        XCTAssertFalse(state.isDiagnosisPresented, "跳转时面板没收起（用户看不到树）")
        print("🧪 链接读数：\(linked.map(\.text)) → \(request.id)")
    }

    /// 反例面：**词中间切一刀会跳到别的对象** —— 长名里不许认出短名。
    func testNamesInsideLongerIdentifiersAreNotLinked() {
        let target = DiagnosisObjectLinker.Target(kind: .table, name: "orders", schema: "public")

        func texts(_ text: String) -> [String] {
            DiagnosisObjectLinker.segments(in: text, targets: [target]).filter { $0.target != nil }.map(\.text)
        }

        XCTAssertEqual(texts("orders 的扫描次数偏高"), ["orders"], "独立出现的表名没被认出来")
        XCTAssertEqual(texts("orders_archive 与 myorders 都不是 orders"), ["orders"], "词中间被切开了")
        XCTAssertEqual(texts("Orders 大写也应该认"), ["Orders"], "大小写不同就认不出来")
        XCTAssertEqual(texts("public.orders 这个限定名"), ["public.orders"], "限定名没整段认出来")
        XCTAssertEqual(texts("没有任何对象名的一句话"), [], "没出现对象名却给了链接")
    }

    // MARK: - ① 上下文进提示词（模型看到的就是面板上那些）

    @MainActor
    func testPromptCarriesTheContextForTheModel() async throws {
        let (state, config) = await makeState()
        _ = addTab(to: state, config: config, receipt: receipt())
        state.beginObjectDiagnosis(for: ordersTable())

        let service = ScriptedService(config: config) { sql in
            sql.contains("pg_stat_user_tables")
                ? self.result(["schemaname", "relname", "seq_scan", "idx_scan", "n_live_tup", "bytes"],
                              [["public", "orders", "42", "0", "3", "8192"]])
                : nil
        }
        state.serviceOverride = service
        await state.gatherDiagnosisEvidence(sql: state.diagnosisTargetSQL)

        let prompt = state.diagnosisContext.boundedPromptText(language: .simplifiedChinese)
        XCTAssertTrue(prompt.contains("public.orders"), "提示词里没有对象名")
        XCTAssertTrue(prompt.contains("shop"), "提示词里没有库")
        XCTAssertTrue(prompt.contains("probe"), "提示词里没有连接")
        XCTAssertTrue(prompt.contains("12 ms"), "提示词里没有最近一次执行的耗时：\(prompt.prefix(200))")
        XCTAssertTrue(prompt.contains("select * from orders where id > 10"), "提示词里没有最近一次执行的语句")
        XCTAssertTrue(prompt.contains("objectStats"), "提示词里没有对象统计这条证据")
    }
}
