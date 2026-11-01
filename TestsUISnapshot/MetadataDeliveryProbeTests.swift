import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 元数据面「从界面点下去」这一段的机器判据（v0.3.0 B3 批次）。
///
/// 台账那两行的旧备注是「界面呈现待人工确认」（`FR-STD-DB-META-011`）与
/// 「界面点击待人工点验」（`FR-STD-DB-META-015`）。这两句话真正没被机器判过的只有**最后一跳**：
/// - 011：右键「查看 DDL」→ `AppState.performTreeAction(.viewDDL, …)` → `openObjectDDL`
///   → 取服务端定义体 → 装配 → **落进新页签**；
/// - 015：搜索拿到命中之后，点「浏览数据」→ `AppState.browseSearchHit` → 新页签里的语句
///   必须指**那个命中对象**（限定名 + LIMIT），并且**真的执行**。
///
/// 判法：真 `AppState` + 真集群（与界面同一条链：`performTreeAction` / `searchObjects` /
/// `browseSearchHit` 都是生产入口，没有探针专用旁路），读**页签里到底写了什么**。
///
/// 边界（如实登记）：
/// · 要真集群：由 `Scripts/run-manual-verification-probes.sh` 注入 `DOYAH_PROBE_PG*`；没注入就跳过
///   （跳过 ≠ 通过）；
/// · 不判**鼠标**：右键菜单项的存在与作用行由 `ObjectTreeContextMenuProbeTests` 判；
///   搜索面板的输入框打字 / 250ms 防抖手感不进本文件（面板只做防抖与呈现，匹配在 Core）；
/// · 函数重载只判「两个签名都在」；视图定义体逐字内容归服务端（`pg_get_viewdef`）。
final class MetadataDeliveryProbeTests: XCTestCase {

    private var host = "127.0.0.1"
    private var port = 55433
    private var user = "postgres"
    private var database = ""

    private static let scratchSuffix = "meta_delivery"
    private static let selectedConnectionDefaultsKey = "settings.selectedConnectionID"
    private var savedSelectedConnection: String?

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "元数据交付面探针要真库：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）"
        )
        let env = ProcessInfo.processInfo.environment
        guard let scratchDatabase = env["DOYAH_PROBE_PGMETA"] else {
            throw XCTSkip(
                "元数据交付面探针要真集群：请走 Scripts/run-manual-verification-probes.sh"
                    + "（它起本机档并注入 DOYAH_PROBE_PG*）—— 跳过不算通过，脚本会核对证据文件"
            )
        }
        database = scratchDatabase
        host = env["DOYAH_PROBE_PGHOST"] ?? host
        port = Int(env["DOYAH_PROBE_PGPORT"] ?? "") ?? port
        user = env["DOYAH_PROBE_PGUSER"] ?? user
        savedSelectedConnection = UserDefaults.standard.string(forKey: Self.selectedConnectionDefaultsKey)
    }

    override func tearDownWithError() throws {
        if let saved = savedSelectedConnection {
            UserDefaults.standard.set(saved, forKey: Self.selectedConnectionDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedConnectionDefaultsKey)
        }
    }

    // MARK: - 连接与现场

    private func config(database: String) -> ConnectionConfig {
        ConnectionConfig(
            name: "元数据交付探针",
            dbType: .postgresql,
            host: host,
            port: port,
            database: database,
            username: user,
            sslMode: .disable,
            timeout: 5
        )
    }

    /// 现场**由探针自己造、自己拆**：不依赖脚本里那几份夹具，换一台集群也能复跑。
    ///
    /// 两个 schema 各一张**同名表**（`mkt_orders`）—— 跨 schema 搜索到底有没有把两边都列出来，
    /// 同名才是判得动的那一份输入；再加一个视图（视图定义体走服务端）、一个函数（两个重载）、
    /// 一个 `mkt_` 开头的列名（列命中）。
    private func makeFixture() async throws {
        let admin = PostgresService(config: config(database: "postgres"), password: nil)
        _ = try await admin.connect()
        try await run(
            "DROP DATABASE IF EXISTS \"\(database)\" WITH (FORCE);",
            on: admin
        )
        try await run("CREATE DATABASE \"\(database)\";", on: admin)
        await admin.disconnect()

        let service = PostgresService(config: config(database: database), password: nil)
        _ = try await service.connect()
        try await run(
            """
            CREATE SCHEMA probe_a;
            CREATE SCHEMA probe_b;
            CREATE TABLE probe_a.mkt_orders (id int, mkt_note text);
            CREATE TABLE probe_b.mkt_orders (id int);
            CREATE VIEW probe_a.mkt_orders_view AS SELECT id FROM probe_a.mkt_orders;
            CREATE FUNCTION probe_a.mkt_fn(p int) RETURNS int LANGUAGE sql AS 'SELECT $1 + 1';
            CREATE FUNCTION probe_a.mkt_fn(p text) RETURNS text LANGUAGE sql AS 'SELECT $1';
            """,
            on: service
        )
        await service.disconnect()
    }

    private func run(_ sql: String, on service: any DatabaseService) async throws {
        for try await _ in service.execute(sql, options: .default) {}
    }

    @MainActor
    private func makeAppState() async -> AppState {
        let state = AppState()
        await state.startupChain?.value
        let cfg = config(database: database)
        state.connections = [cfg]
        state.selectedConnectionID = cfg.id
        return state
    }

    @MainActor
    private func disconnectAndSettle(_ state: AppState) async {
        await state.disconnectObjectTree()
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func waitFor(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func node(
        kind: DatabaseObject.Kind,
        schema: String,
        name: String
    ) -> DatabaseObject {
        DatabaseObject(
            id: "db:\(database)|schema:\(schema)|\(kind.rawValue):\(name)",
            name: name,
            kind: kind,
            database: database,
            schema: schema
        )
    }

    // MARK: - FR-STD-DB-META-011：查看 DDL 真的落到页签里

    @MainActor
    func testViewAndFunctionDDLLandInANewTabThroughTheProductionAction() async throws {
        try await makeFixture()
        let state = await makeAppState()

        // ① 视图：定义体只能从服务端取 ⇒ 这一段判的是「取回 → 装配 → 落页签」整条链。
        let view = node(kind: .view, schema: "probe_a", name: "mkt_orders_view")
        let tabsBefore = state.tabs.count
        await state.performTreeAction(.viewDDL, on: view)
        try await waitFor { state.tabs.count == tabsBefore + 1 && !(state.tabs.last?.sql.isEmpty ?? true) }

        guard let viewTab = state.tabs.last else { return XCTFail("没有新页签") }
        XCTAssertTrue(
            viewTab.sql.contains("CREATE OR REPLACE VIEW"),
            "视图 DDL 必须是等价建视图语句，实际：\(viewTab.sql.prefix(200))"
        )
        XCTAssertTrue(
            viewTab.sql.contains("\"probe_a\".\"mkt_orders_view\""),
            "限定名丢了（跨 schema 会落到别的同名视图上），实际：\(viewTab.sql.prefix(200))"
        )
        XCTAssertTrue(
            viewTab.sql.contains("FROM probe_a.mkt_orders"),
            "定义体没带上（装配成了空壳），实际：\(viewTab.sql.prefix(300))"
        )
        XCTAssertTrue(viewTab.results.isEmpty, "查看 DDL 只许写进编辑器，不许执行")
        XCTAssertEqual(viewTab.sourceTable, nil, "DDL 页签不该带来源表（会被内联编辑当成可编辑结果）")

        // ② 函数：两个同名重载都必须出现（只取第一条 = 让人以为这个函数只有一种签名）。
        let function = node(kind: .function, schema: "probe_a", name: "mkt_fn")
        let tabsAfterView = state.tabs.count
        await state.performTreeAction(.viewDDL, on: function)
        try await waitFor { state.tabs.count == tabsAfterView + 1 && !(state.tabs.last?.sql.isEmpty ?? true) }

        guard let functionTab = state.tabs.last else { return XCTFail("函数 DDL 没有新页签") }
        let signatureCount = functionTab.sql.components(separatedBy: "CREATE OR REPLACE FUNCTION").count - 1
        XCTAssertEqual(
            signatureCount, 2,
            "函数有两个重载，页签里应有两段建函数语句，实际 \(signatureCount) 段：\(functionTab.sql.prefix(400))"
        )
        XCTAssertTrue(functionTab.sql.contains("mkt_fn"), "建函数语句里没有目标函数名")

        // ③ 表：走「读列 + 拼装」那条老路（列未加载时必须先加载，不许猜列）。
        let table = node(kind: .table, schema: "probe_a", name: "mkt_orders")
        let tabsAfterFunction = state.tabs.count
        await state.performTreeAction(.viewDDL, on: table)
        try await waitFor { state.tabs.count == tabsAfterFunction + 1 && !(state.tabs.last?.sql.isEmpty ?? true) }
        guard let tableTab = state.tabs.last else { return XCTFail("表 DDL 没有新页签") }
        XCTAssertTrue(tableTab.sql.hasPrefix("CREATE TABLE"), "表 DDL 应以 CREATE TABLE 开头：\(tableTab.sql.prefix(120))")
        XCTAssertTrue(tableTab.sql.contains("\"mkt_note\""), "列清单里少了 mkt_note：\(tableTab.sql.prefix(300))")

        try writeEvidence(
            "ddl",
            [
                "viewTab": viewTab.sql,
                "functionTab": functionTab.sql,
                "tableTab": tableTab.sql,
                "tabsBefore": tabsBefore,
                "tabsAfter": state.tabs.count,
            ]
        )
        await disconnectAndSettle(state)
    }

    // MARK: - FR-STD-DB-META-015：搜索命中 → 浏览那一下

    @MainActor
    func testSearchFindsObjectsAcrossSchemasAndBrowseUsesTheHit() async throws {
        try await makeFixture()
        let state = await makeAppState()

        let outcome = try await state.searchObjects("mkt")
        let names = outcome.matches.map { $0.hit.qualifiedName }

        XCTAssertTrue(names.contains("probe_a.mkt_orders"), "跨 schema 搜索漏了 probe_a.mkt_orders：\(names)")
        XCTAssertTrue(names.contains("probe_b.mkt_orders"), "同名表在另一个 schema 里的那一条漏了：\(names)")
        XCTAssertTrue(names.contains("probe_a.mkt_orders_view"), "视图命中漏了：\(names)")
        XCTAssertTrue(names.contains("probe_a.mkt_fn"), "函数命中漏了：\(names)")
        XCTAssertTrue(
            outcome.matches.contains { $0.hit.kind == .column && $0.hit.name.contains("mkt_note") },
            "列命中漏了（列名也参与搜索）：\(names)"
        )
        XCTAssertGreaterThanOrEqual(outcome.totalHits, 5, "命中总数应覆盖现场造的那五个对象：\(outcome.totalHits)")

        // 浏览：点中 `probe_b.mkt_orders` 之后，新页签里的语句必须指**这一张**表（不是同名的那张）。
        let tabsBefore = state.tabs.count
        state.browseSearchHit(schema: "probe_b", name: "mkt_orders")
        try await waitFor { state.tabs.count == tabsBefore + 1 && !(state.tabs.last?.sql.isEmpty ?? true) }

        guard let tab = state.tabs.last else { return XCTFail("浏览没有新页签") }
        XCTAssertTrue(
            tab.sql.contains("\"probe_b\".\"mkt_orders\""),
            "浏览语句没指到命中的那个 schema（会打开另一张同名表）：\(tab.sql)"
        )
        XCTAssertTrue(
            tab.sql.uppercased().contains("LIMIT 200"),
            "浏览语句应带默认 200 行上限：\(tab.sql)"
        )
        XCTAssertEqual(tab.sourceTable?.schema, "probe_b", "来源表没记下来（内联编辑会拒编辑）")
        XCTAssertEqual(tab.sourceTable?.name, "mkt_orders", "来源表名不对")

        try writeEvidence(
            "search",
            [
                "keyword": "mkt",
                "matches": names,
                "totalHits": outcome.totalHits,
                "browseTab": tab.sql,
            ]
        )
        await disconnectAndSettle(state)
    }

    // MARK: - 证据

    private func writeEvidence(_ caseName: String, _ payload: [String: Any]) throws {
        let directory = UISnapshot.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var enriched = payload
        enriched["case"] = caseName
        enriched["database"] = database
        enriched["host"] = "\(host):\(port)"
        let data = try JSONSerialization.data(
            withJSONObject: enriched,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: directory.appendingPathComponent("metadata-delivery-evidence-\(caseName).json"),
            options: .atomic
        )
    }
}
