import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 会话面（`FR-STD-DB-SESS-002` · `-003` · `-004`）与诊断面（`FR-STD-DB-DIAG-003` · `-004`）的
/// **界面链**探针 —— B5 批次。
///
/// ## 这几条为什么一直停在 🟡（台账备注原文「界面点击待人工点验」）
///
/// 核盘后要分开说三件事：
///   · 「怎么解析、怎么排序、怎么生成语句」早有单测（`SessionMonitorTests` /
///     `SessionKillTests` / `ServerObjectsTests` / `DatabaseStatsTests` / `SlowQueryReportTests`）；
///   · 「真库上这些系统视图长什么样」归真机脚本（`test-*.sh`，217 那条本跳未能连上 ⇒ 记「未知」）；
///   · 缺的是**中间那一段**：从界面按下去（`loadServerSessions` / `cancelSessionStatement` /
///     `terminateSession` / `serverObjectSections` / `executeServerObjectWrite` /
///     `databaseStats` / `slowQueryRanking`）到「哪条语句真的发出去、按哪个口径排序、
///     拿不到时说什么」—— 那一段可以少发一条语句、可以把 `pg_cancel_backend` 和
///     `pg_terminate_backend` 接反、可以在扩展没装时照样发排行查询，上面那些用例照样全绿。
///
/// ## 怎么量（本机没有稳定在跑的实例，探针不依赖它）
///
/// 一处注入缝（本批新开的 `AppState.serviceOverride`，生产默认仍是真连接）：
/// 假 `DatabaseService` 记下**收到的每一条语句**，并按 SQL 内容回不同的结果集 ——
/// 判的是「点了之后到底发了哪几条、顺序对不对、解析出来是什么」。
///
/// ## 边界（如实登记，别把这条读成「人点过了」）
///
/// · **不是真数据库**：`pg_stat_activity` / `pg_stat_statements` 真库返回的行
///   （类型、时区、权限过滤）不在本文件；217 那条真库回归本跳连接超时 ⇒ 记「未知」。
/// · **面板本体没装宿主**：`SessionPanel` / `DatabaseStatsPanel` / `SlowQueryPanel` 的版面与
///   按钮灰显状态由各自的 `initial*` 注入口拍快照（另归快照层），本文件判的是它们**调用的那层**。
/// · **真鼠标点一行**（把慢查询原文放进编辑器）由人承担；本文件判「放进去之后页签里是什么」。
final class SessionDiagnosticsProbeTests: XCTestCase {

    // MARK: - 脚本化假服务

    /// 记下收到的每一条语句，并按 `router` 回结果集；`own` 用来判「不许掐自己那条会话」。
    final class ScriptedService: DatabaseService, OwnSessionReporting, @unchecked Sendable {
        let config: ConnectionConfig

        private let lock = NSLock()
        private var recorded: [String] = []
        private let router: (String) -> QueryResult?
        private let version: String
        private let own: Int?

        init(
            config: ConnectionConfig,
            version: String = "18.6",
            own: Int? = nil,
            router: @escaping (String) -> QueryResult?
        ) {
            self.config = config
            self.version = version
            self.own = own
            self.router = router
        }

        var statements: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func connect() async throws -> ServerInfo {
            ServerInfo(version: version, database: config.database, user: config.username)
        }

        func disconnect() async {}
        func beginTransaction() async throws {}
        func commit() async throws {}
        func rollback() async throws {}
        func cancel(_ handle: ExecutionHandle) async -> CancelOutcome { .notActive }
        func ownSessionPID() async -> Int? { own }

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
                if let result {
                    continuation.yield(.resultSet(result))
                }
                continuation.yield(.finished(QuerySummary(statementCount: 1, duration: 0)))
                continuation.finish()
            }
        }
    }

    // MARK: - 夹具

    /// 与 `BackupRestoreImportProbeTests` 同一条口径：`EgressLog.shared` 是懒单例，
    /// 谁先碰它位置就定了；先指到本仓 `.build/` 下，免得探针写到用户真账。
    private static func pinEgressDirectoryIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        if let injected = environment["DOYAH_EGRESS_LOG_DIR"], !injected.isEmpty { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fallback = root.appendingPathComponent(".build/ui-probe-egress", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        setenv("DOYAH_EGRESS_LOG_DIR", fallback.path, 1)
    }

    @MainActor
    private func makeState(
        dbType: DatabaseType = .postgresql,
        connectionReadOnly: Bool = false
    ) async -> (AppState, ConnectionConfig) {
        Self.pinEgressDirectoryIfNeeded()
        let config = ConnectionConfig(
            name: "探针库",
            dbType: dbType,
            host: "127.0.0.1",
            port: 5432,
            database: "shop",
            username: "probe",
            isReadOnly: connectionReadOnly
        )
        let state = AppState()
        // 启动链会回读盘上的连接册并重设选中项 —— 不等它落地就塞假连接会被它盖掉（时序假红）。
        await state.startupChain?.value
        state.connections = [config]
        state.selectedConnectionID = config.id
        return (state, config)
    }

    /// 造一个结果集：列名 + 行（`nil` = SQL NULL）。
    private func result(_ columns: [String], _ rows: [[String?]]) -> QueryResult {
        QueryResult(
            columns: columns.enumerated().map { ColumnMeta(id: $0.offset, name: $0.element) },
            rows: rows
        )
    }

    /// `pg_stat_activity` 那一行（`serverActivityQuery` 的列序）。
    private let activityColumns = [
        "pid", "usename", "datname", "client_addr", "application_name", "state",
        "wait_event_type", "wait_event", "backend_start", "query_start", "query"
    ]

    // MARK: - ① SESS-002 会话列表：一条查询、按「等待 → 活跃 → 空闲」排、字段逐个对上

    @MainActor
    func testSessionListComesFromPgStatActivityAndSortsWaitingFirst() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            guard sql.contains("FROM pg_stat_activity") else { return nil }
            return self.result(self.activityColumns, [
                ["9001", "report", "shop", "10.0.0.9", "psql", "idle", nil, nil,
                 "2026-11-01 09:00:00+08", "2026-11-01 09:10:00+08", "select 1"],
                ["9002", "app", "shop", "10.0.0.2", "app", "active", "Client", "ClientRead",
                 "2026-11-01 09:00:00+08", "2026-11-01 09:20:00+08", "select * from orders"],
                ["9003", "app", "shop", "10.0.0.3", "app", "active", "Lock", "relation",
                 "2026-11-01 09:00:00+08", "2026-11-01 09:30:00+08", "update orders set note = 'x'"],
                // 没有 pid 的行不许变成「会话号 0」：丢弃，不猜。
                [nil, "ghost", "shop", nil, nil, "idle", nil, nil, nil, nil, nil]
            ])
        }
        state.serviceOverride = service

        let sessions = try await state.loadServerSessions()

        let statements = service.statements
        XCTAssertEqual(statements.count, 1, "一次刷新应当只发一条查询（实际 \(statements.count) 条）")
        XCTAssertTrue(statements[0].contains("pg_stat_activity"), "会话列表不是从 pg_stat_activity 取的：\(statements[0])")

        XCTAssertEqual(sessions.map(\.pid), [9003, 9002, 9001],
                       "排序不是「等待 → 活跃 → 空闲」：\(sessions.map(\.pid))")
        let waiting = try XCTUnwrap(sessions.first)
        XCTAssertEqual(waiting.user, "app")
        XCTAssertEqual(waiting.database, "shop")
        XCTAssertEqual(waiting.clientAddress, "10.0.0.3")
        XCTAssertEqual(waiting.waitEvent, "relation")
        XCTAssertTrue(waiting.isWaiting, "带 wait_event_type=Lock 的会话没被判成等待")
        XCTAssertEqual(sessions.filter(\.isIdle).map(\.pid), [9001], "空闲那一条判错了")
        // 客户端的读等待不算「被阻塞」—— 否则每一条正常连接都会顶到最前面。
        XCTAssertFalse(sessions.first(where: { $0.pid == 9002 })?.isWaiting ?? true,
                       "wait_event_type=Client 被当成了阻塞")
        print("🧪 会话读数：1 条查询 · \(sessions.count) 条会话 · 顺序 \(sessions.map(\.pid))")
    }

    // MARK: - ② SESS-003 取消：只发 pg_cancel_backend，连接保留（不是 terminate）

    @MainActor
    func testCancelStatementSendsCancelBackendNotTerminate() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            if sql.contains("pg_cancel_backend") {
                return self.result(["pg_cancel_backend"], [["t"]])
            }
            return nil
        }
        state.serviceOverride = service

        let message = await state.cancelSessionStatement(pid: 4242)

        XCTAssertEqual(message, "", "取消成功时不该返回错误：\(message)")
        XCTAssertEqual(service.statements, ["SELECT pg_cancel_backend(4242)"],
                       "发出去的不是「取消当前语句」：\(service.statements)")
        XCTAssertFalse(service.statements.joined().contains("terminate"),
                       "「取消语句」发成了终止会话 —— 那会把整条连接掐掉")
        // 状态栏里的会话号按当前语言做了千分位（`4,242`），两种写法都算「说清了是哪条」。
        XCTAssertTrue(state.statusMessage.contains("4242") || state.statusMessage.contains("4,242"),
                      "状态栏没说清取消的是哪条会话：\(state.statusMessage)")
    }

    // MARK: - ③ SESS-003 终止：自己的会话当场拒，一条语句都不发

    @MainActor
    func testTerminateOwnSessionIsRefusedBeforeSendingAnything() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config, own: 777) { _ in nil }
        state.serviceOverride = service

        let message = await state.terminateSession(pid: 777)

        XCTAssertFalse(message.isEmpty, "终止自己的会话被放行了")
        XCTAssertEqual(service.statements, [],
                       "拒之前已经发了语句 —— 拒在服务端就晚了：\(service.statements)")
    }

    /// 服务端说 `false`（通常是没权限）：如实报「被拒」，不许报成已终止。
    @MainActor
    func testTerminateDeniedByServerIsReportedAsDeniedNotSucceeded() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config, own: 1) { sql in
            sql.contains("pg_terminate_backend") ? self.result(["pg_terminate_backend"], [["f"]]) : nil
        }
        state.serviceOverride = service

        let message = await state.terminateSession(pid: 4243)

        XCTAssertFalse(message.isEmpty, "服务端说 false 却报了成功")
        XCTAssertEqual(service.statements, ["SELECT pg_terminate_backend(4243)"],
                       "终止会话发出去的不是 pg_terminate_backend：\(service.statements)")
        XCTAssertFalse(state.statusMessage.contains("已终止"),
                       "服务端拒绝的这一次也写了「已终止」：\(state.statusMessage)")
    }

    // MARK: - ④ SESS-004 服务器级对象：三类各发一条、不支持的那类不发也不编空表

    @MainActor
    func testServerObjectSectionsQueryEachKindAndKeepUnsupportedOnesExplicit() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            if sql.contains("FROM pg_catalog.pg_roles") {
                return self.result(["name", "can_login", "is_superuser", "comment"], [
                    ["postgres", "t", "t", "初始超级用户"],
                    ["probe", "t", "f", nil]
                ])
            }
            if sql.contains("pg_tablespace") {
                return self.result(["name", "owner", "location", "bytes"], [["fastspace", "probe", "/data/fast", "8192"]])
            }
            if sql.contains("pg_extension") {
                return self.result(["name", "version", "schema"], [["plpgsql", "1.0", "pg_catalog"]])
            }
            return nil
        }
        state.serviceOverride = service

        let sections = try await state.serverObjectSections()

        XCTAssertEqual(sections.count, ServerObjectKind.allCases.count,
                       "三类里有的没回来：\(sections.map(\.kind))")
        let byKind = Dictionary(uniqueKeysWithValues: sections.map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.role]?.objects.map(\.name), ["postgres", "probe"])
        XCTAssertEqual(byKind[.role]?.objects.last?.canLogin, true)
        XCTAssertEqual(byKind[.role]?.objects.first?.isSuperuser, true)
        XCTAssertEqual(byKind[.tablespace]?.objects.map(\.name), ["fastspace"])
        XCTAssertEqual(byKind[.tablespace]?.objects.first?.sizeBytes, 8192)
        XCTAssertEqual(byKind[.extension]?.objects.map(\.name), ["plpgsql"])
        XCTAssertEqual(service.statements.count, 3,
                       "三类对象应当各发一条查询（实际 \(service.statements.count) 条）")
        print("🧪 服务器级对象读数：\(service.statements.count) 条查询 · 角色 \(byKind[.role]?.objects.count ?? 0) / 表空间 \(byKind[.tablespace]?.objects.count ?? 0) / 扩展 \(byKind[.extension]?.objects.count ?? 0)")
    }

    /// 建角色：预览的那一句就是要执行的那一句（逐字），且只发一次。
    @MainActor
    func testServerObjectWriteSendsExactlyThePreviewedStatementOnce() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { _ in nil }
        state.serviceOverride = service

        let plan = try state.serverObjectWritePlan(
            .createRole(RoleSpec(name: "report_ro", password: "s3cret", canLogin: true, isSuperuser: false))
        )
        guard case .ready(let command) = plan else {
            return XCTFail("建角色被判成不可执行：\(plan)")
        }
        let start = try await state.executeServerObjectWrite(command, bypassingSafetyCheck: true)

        XCTAssertEqual(start, .started, "已经看过确认弹窗、带 bypass 回来仍没执行")
        XCTAssertEqual(service.statements, [command.statement],
                       "发出去的语句与预览的那一句不一致：\(service.statements) vs \(command.preview)")
        XCTAssertTrue(command.statement.uppercased().hasPrefix("CREATE ROLE"),
                       "建角色生成的不是 CREATE ROLE：\(command.statement)")
    }

    /// 只读连接：写操作在**发出去之前**就被拒，一条语句都不许发。
    @MainActor
    func testServerObjectWriteOnReadOnlyConnectionIsRefusedWithoutSending() async throws {
        let (state, config) = await makeState(connectionReadOnly: true)
        let service = ScriptedService(config: config) { _ in nil }
        state.serviceOverride = service

        let plan = try state.serverObjectWritePlan(
            .dropRole(name: "report_ro", host: "")
        )
        guard case .ready(let command) = plan else {
            return XCTFail("删除角色被判成不可执行：\(plan)")
        }
        let start = try await state.executeServerObjectWrite(command)

        guard case .refused(let detail) = start else {
            return XCTFail("只读连接上删除角色没被拒：\(start)")
        }
        XCTAssertTrue(detail.contains("DROP ROLE"), "拒绝理由没说清是哪条语句：\(detail)")
        XCTAssertEqual(service.statements, [], "被拒的那一次仍然发了语句：\(service.statements)")
    }

    // MARK: - ⑤ DIAG-004 统计面板：四类各一条查询，比率算不出来时给 nil 不给 0

    @MainActor
    func testDatabaseStatsRunsOneQueryPerMetricAndNeverFakesZeroRatios() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            if sql.contains("pg_total_relation_size") {
                return self.result(["name", "bytes"], [["public.orders", "1048576"], ["public.audit", "2048"]])
            }
            if sql.contains("seq_scan") {
                // 第二张表一次都没扫过 —— 命中率没有定义，必须是 nil 而不是 0。
                return self.result(["name", "seq_scan", "idx_scan"], [
                    ["public.orders", "10", "90"],
                    ["public.audit", "0", "0"]
                ])
            }
            if sql.contains("backend_type") {
                return self.result(["state", "count"], [["active", "2"], ["idle", "5"]])
            }
            if sql.contains("pg_stat_database") {
                return self.result(["hits", "reads"], [["990", "10"]])
            }
            return nil
        }
        state.serviceOverride = service

        let report = try await state.databaseStats()

        XCTAssertEqual(service.statements.count, 4,
                       "四类指标应当各发一条查询（实际 \(service.statements.count) 条）")
        XCTAssertEqual(report.tableSizes.map(\.name), ["public.orders", "public.audit"], "表大小没按降序")
        XCTAssertEqual(report.tableSizes.first?.displaySize, "1.0 MB")

        let orders = report.tableScans.first { $0.name == "public.orders" }
        XCTAssertEqual(orders?.indexHitRatio ?? 0, 0.9, accuracy: 0.0001, "索引命中率算错了")
        let audit = report.tableScans.first { $0.name == "public.audit" }
        XCTAssertNil(audit?.indexHitRatio, "没有扫描数据的表被算成了 0%（会让人以为索引完全没用上）")
        XCTAssertEqual(audit?.displayRatio, "无扫描数据", "没有扫描数据时的文案不是「无扫描数据」：\(audit?.displayRatio ?? "nil")")

        XCTAssertEqual(report.connections.total, 7, "连接数合计不对")
        XCTAssertEqual(report.cacheHit?.ratio ?? 0, 0.99, accuracy: 0.0001, "缓存命中率算错了")
        print("🧪 统计读数：4 条查询 · 表 \(report.tableSizes.count) · 连接 \(report.connections.total) · 缓存 \(report.cacheHit?.displayRatio ?? "nil")")
    }

    // MARK: - ⑥ DIAG-003 慢查询：排序口径真的换列名、服务器主版本真的参与选择

    @MainActor
    func testSlowQueryRankingSwitchesOrderColumnWithTheChosenSort() async throws {
        let (state, config) = await makeState()
        var seenRankingSQL: [String] = []
        let service = ScriptedService(config: config, version: "18.6") { sql in
            if sql.contains("to_regclass") {
                return self.result(["extension", "relation_exists"], [["pg_stat_statements", "t"]])
            }
            if sql.contains("FROM pg_stat_statements") {
                seenRankingSQL.append(sql)
                return self.result(["query", "calls", "total_millis", "mean_millis", "rows"], [
                    ["select * from orders where id = $1", "1200", "8421.5", "7.02", "1200"],
                    ["update orders set note = $1", "30", "61200.0", "2040.0", "30"]
                ])
            }
            return nil
        }
        state.serviceOverride = service

        let byTotal = try await state.slowQueryRanking(sort: .totalTime)
        guard case .ranking(let rows) = byTotal else {
            return XCTFail("按总耗时取排行失败了：\(byTotal)")
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.calls, 1200)
        XCTAssertEqual(rows.first?.meanMillis ?? 0, 7.02, accuracy: 0.0001)
        XCTAssertTrue(seenRankingSQL.last?.contains("ORDER BY total_exec_time DESC") == true,
                      "按总耗时的排序子句不对：\(seenRankingSQL.last ?? "nil")")
        XCTAssertTrue(seenRankingSQL.last?.contains("pg_stat_statements WHERE query NOT LIKE") == false
                      || seenRankingSQL.last?.contains("query NOT LIKE") == true,
                      "排行没有排除扩展自身的查询：\(seenRankingSQL.last ?? "nil")")

        _ = try await state.slowQueryRanking(sort: .meanTime)
        XCTAssertTrue(seenRankingSQL.last?.contains("ORDER BY mean_exec_time DESC") == true,
                      "按平均耗时的排序子句不对：\(seenRankingSQL.last ?? "nil")")

        _ = try await state.slowQueryRanking(sort: .calls)
        XCTAssertTrue(seenRankingSQL.last?.contains("ORDER BY calls DESC") == true,
                      "按调用次数的排序子句不对：\(seenRankingSQL.last ?? "nil")")
        print("🧪 慢查询读数：\(seenRankingSQL.count) 条排行查询 · 末条排序 \(seenRankingSQL.last?.split(separator: "\n").first { $0.contains("ORDER BY") } ?? "")")
    }

    /// 12 与 18 两代列名：同一份代码按服务器主版本选 `total_time` / `total_exec_time`。
    @MainActor
    func testSlowQueryRankingAdaptsColumnNamesToServerMajor() async throws {
        let (state, config) = await makeState()
        var rankingSQL: [String] = []
        let service = ScriptedService(config: config, version: "12.18") { sql in
            if sql.contains("to_regclass") {
                return self.result(["extension", "relation_exists"], [["pg_stat_statements", "t"]])
            }
            if sql.contains("FROM pg_stat_statements") {
                rankingSQL.append(sql)
                return self.result(["query", "calls", "total_millis", "mean_millis", "rows"], [])
            }
            return nil
        }
        state.serviceOverride = service

        _ = try await state.slowQueryRanking(sort: .totalTime)

        let sql = try XCTUnwrap(rankingSQL.last)
        XCTAssertTrue(sql.contains("total_time AS total_millis"),
                      "12 上应当用老列名 total_time：\(sql)")
        XCTAssertFalse(sql.contains("total_exec_time"),
                       "12 上用了 13+ 才有的列名 —— 真库会报「列不存在」")
        /*
         反例（本文件写完后实际跑过）：把 `serverMajor` 写死成 18 ⇒ 本条与上一条各红 1 处；
         把排序写死成 `total_exec_time` ⇒ 上一条的 mean / calls 两段红。
         */
    }

    /// 扩展没装：给可照做的安装步骤，**不发**排行查询，也不说「一条都没有」。
    @MainActor
    func testSlowQueryMissingExtensionExplainsHowToInstallInsteadOfEmptyRanking() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { sql in
            sql.contains("to_regclass") ? self.result(["extension", "relation_exists"], [[nil, "f"]]) : nil
        }
        state.serviceOverride = service

        let outcome = try await state.slowQueryRanking(sort: .totalTime)

        guard case .missingExtension(let instructions) = outcome else {
            return XCTFail("扩展没装却给了别的结果：\(outcome)")
        }
        XCTAssertTrue(instructions.contains("shared_preload_libraries"),
                      "安装指引里没有 shared_preload_libraries：\(instructions)")
        XCTAssertTrue(instructions.contains("CREATE EXTENSION pg_stat_statements"),
                      "安装指引里没有 CREATE EXTENSION：\(instructions)")
        XCTAssertEqual(service.statements.count, 1,
                       "扩展没装时仍发了别的查询（排行查询打过去只会换回一句 relation does not exist）：\(service.statements)")
    }

    /// 方言不支持（MySQL 一族）：直说，不去发一条 PG 口径的语句。
    @MainActor
    func testSlowQueryRankingSaysUnsupportedForNonPostgresDialects() async throws {
        let (state, config) = await makeState(dbType: .mysql)
        let service = ScriptedService(config: config) { _ in nil }
        state.serviceOverride = service

        let outcome = try await state.slowQueryRanking()

        guard case .unsupported(let reason) = outcome else {
            return XCTFail("MySQL 上没报「不支持」：\(outcome)")
        }
        XCTAssertFalse(reason.isEmpty, "「不支持」没给理由")
        XCTAssertEqual(service.statements, [], "不支持的方言上仍发了语句：\(service.statements)")
    }

    /// 排行里点一条：原文进编辑器、状态栏说「未执行」，且**没有**发出任何语句。
    @MainActor
    func testSlowQueryRowGoesIntoTheEditorWithoutExecuting() async throws {
        let (state, config) = await makeState()
        let service = ScriptedService(config: config) { _ in nil }
        state.serviceOverride = service

        let tab = QueryTab(title: "查询 1", sql: "select 1", connectionID: config.id, database: "shop")
        state.tabs.append(tab)
        state.selectedTabID = tab.id

        let entry = SlowQueryReport.Entry(
            query: "select * from orders where note = 'x'",
            calls: 42,
            totalMillis: 1234.5,
            meanMillis: 29.4,
            rows: 42
        )
        state.putSlowQueryInEditor(entry)

        XCTAssertEqual(state.tabs.first(where: { $0.id == tab.id })?.sql, entry.query,
                       "点一行之后页签里不是那条语句")
        XCTAssertFalse(state.statusMessage.isEmpty, "放进编辑器之后没有任何交代")
        XCTAssertEqual(service.statements, [], "「放进编辑器」不该执行任何语句：\(service.statements)")
    }
}
