import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 验收条目 `AC-ALL-GATE-REL-004` / `-005` / `-006` 的**真库端到端**判据。
///
/// ## 为什么单开一片（三条一直停在 🟡/⬜ 的原因）
///
/// 台账原文要求「对**真实 PostgreSQL** 完成：新建连接 → 测试连接 → 执行多语句 → 对象树展开
/// → 结果复制 → 语法检查」/「错误路径可读」/「崩溃零容忍」。盘上原来只有：
/// · `Tests/IntegrationPGTests`（连接 / 几条查询，四段，不含复制与语法检查）；
/// · `TestsUISnapshot/ResultCopyProbeTests`（复制走真剪贴板，但**数据是合成的**，不连库）；
/// · `Scripts/test-connection-errors.sh`（错误文案，走 CLI，缺「错误密码 / 不存在表 / 不合法 SQL」）。
/// 三段各证一半，没有一处把**同一条真连接**上的整条流程跑完 ⇒ 这三条判不了。
///
/// ## 怎么量（每一段都是产品自己的代码，不另写一份逻辑）
///
/// | 段 | 产品入口 |
/// |---|---|
/// | 新建连接 | `ConnectionConfig` + `PostgresService.connect()` |
/// | 测试连接 | `DatabaseServiceFactory.make` + `connect()` + `disconnect()`（与 `ConnectionFormView.testConnection()` 同一条路） |
/// | 执行多语句 | `StatementSplitter` 切分 → 逐条 `PostgresService.execute` |
/// | 对象树展开 | `MetadataService.loadChildren` 服务器→库→schema→表→列 |
/// | 结果复制 | `ResultClipboard.text`（真结果集；真剪贴板那一步由 `ResultCopyProbeTests` 证） |
/// | 语法检查 | `AppState.checkSyntax(for:)`（`serviceOverride` 缝指向**真**service，生产默认同一条收口） |
///
/// ## 边界（如实登记，别把这片读成「人点过了」）
///
/// · 真鼠标不点：判据是模型 / 命令出口与真实回执，界面观感不在内；
/// · 只这一台实例（`DOYAH_IT_PG_HOST` 给的那台）；换版本 / 换网段未测；
/// · 复制那一段判到「剪贴板里该有什么字」，粘进 Excel 之后长什么样不在内。
///
/// 开关：`DOYAH_IT_PG_HOST` / `_PORT` / `_DB` / `_USER` / `_PASSWORD`（与 `IntegrationPGTests` 同一套）。
/// 没给 ⇒ **XCTSkip**（不红、也不假绿）。
final class AcceptanceRealPostgresTests: XCTestCase {

    // MARK: - 环境

    private struct Env {
        var host: String
        var port: Int
        var database: String
        var user: String
        var password: String
    }

    private func env() throws -> Env {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["DOYAH_IT_PG_HOST"], !host.isEmpty else {
            throw XCTSkip("没给 DOYAH_IT_PG_HOST ⇒ 真库判据 skip（REL-004/005/006 要真库才验得了）")
        }
        return Env(
            host: host,
            port: Int(env["DOYAH_IT_PG_PORT"] ?? "5432") ?? 5432,
            database: env["DOYAH_IT_PG_DB"] ?? "postgres",
            user: env["DOYAH_IT_PG_USER"] ?? "postgres",
            password: env["DOYAH_IT_PG_PASSWORD"] ?? ""
        )
    }

    private func configuration(_ env: Env, port: Int? = nil, password: String = "") -> ConnectionConfig {
        ConnectionConfig(
            name: "acceptance",
            dbType: .postgresql,
            host: env.host,
            port: port ?? env.port,
            database: env.database,
            username: env.user,
            timeout: 8
        )
    }

    /// 跑一条 SQL，返回最后一个结果集（列 + 行）；没有结果集时返回空。
    private func run(
        _ service: any DatabaseService,
        _ sql: String
    ) async throws -> QueryResult {
        var last = QueryResult(columns: [], rows: [])
        for try await event in service.execute(sql, options: .default, handle: ExecutionHandle()) {
            if case let .resultSet(result) = event { last = result }
        }
        return last
    }

    // MARK: - 整条链（REL-004 与 REL-006 共用同一份流程）

    private struct ChainReadout {
        var serverVersion: String
        var testedLine: String
        var statementCount: Int
        var insertedRows: Int
        var treeDepth: Int
        var tableColumns: Int
        var tsv: String
        var markdown: String
        var syntaxMessage: String
    }

    /// 真库上把六段跑一遍。表名按实例唯一，跑完 `drop`（失败也 drop，不留垃圾）。
    private func runChain(env: Env) async throws -> ChainReadout {
        let config = configuration(env)
        let table = "it_accept_\(UUID().uuidString.prefix(8).lowercased())"

        // ① 新建连接
        let service = PostgresService(config: config, password: env.password)
        let info = try await service.connect()
        defer { Task { await service.disconnect() } }

        // ② 测试连接（与「测试连接」按钮同一条路：工厂 + connect + disconnect）
        let probe = DatabaseServiceFactory.make(
            for: config,
            password: env.password,
            language: LocalizationManager.shared.effectiveLanguage
        )
        let probed = try await probe.connect()
        await probe.disconnect()
        let testedLine = L(.connectionFormConnected, probed.version, probed.database, probed.user)

        // ③ 执行多语句（产品自己的切分器；逐条在**同一条连接**上跑）
        let script = """
        create table public.\(table) (id int primary key, note text, amount numeric);
        insert into public.\(table) (id, note, amount) values (1, '中文备注', 10.5), (2, null, 20);
        select id, note, amount from public.\(table) order by id;
        """
        let splitter = StatementSplitter(databaseType: .postgresql)
        let statements = splitter.split(script)
        XCTAssertEqual(statements.count, 3, "多语句切分不是 3 条：\(statements.map(\.sql))")

        var last = QueryResult(columns: [], rows: [])
        for statement in statements {
            last = try await run(service, statement.sql)
        }
        XCTAssertEqual(last.rows.count, 2, "多语句最后一条查询应当回两行：\(last.rows)")

        defer { Task { _ = try? await run(service, "drop table if exists public.\(table)") } }

        // ④ 对象树展开：服务器 → 库 → schema → 表 → 列
        let metadata = MetadataService(
            service: service,
            dialect: PostgresDialect(),
            databaseName: config.database,
            serverLabel: "acceptance"
        )
        var depth = 0
        let roots = try await metadata.loadRoot()
        depth = 1
        guard let root = roots.first else { return ChainReadout(serverVersion: info.version, testedLine: testedLine, statementCount: statements.count, insertedRows: last.rows.count, treeDepth: depth, tableColumns: 0, tsv: "", markdown: "", syntaxMessage: "") }

        let databases = try await metadata.loadChildren(of: root)
        XCTAssertTrue(databases.contains { $0.kind == .database && $0.name == config.database },
                      "对象树没列出当前库 \(config.database)：\(databases.map(\.name))")
        guard let databaseNode = databases.first(where: { $0.kind == .database && $0.name == config.database }) else {
            XCTFail("对象树里找不到当前库节点")
            throw XCTSkip("拿不到库节点，后续深度不判")
        }
        depth = 2

        let schemas = try await metadata.loadChildren(of: databaseNode)
        guard let publicSchema = schemas.first(where: { $0.kind == .schema && $0.name == "public" }) else {
            XCTFail("对象树里找不到 public schema：\(schemas.map(\.name))")
            throw XCTSkip("拿不到 schema 节点")
        }
        depth = 3

        let tables = try await metadata.loadChildren(of: publicSchema)
        guard let tableNode = tables.first(where: { $0.kind == .table && $0.name == table }) else {
            XCTFail("对象树没列出刚建的表 \(table)：\(tables.map(\.name))")
            throw XCTSkip("拿不到表节点")
        }
        depth = 4

        let columns = try await metadata.loadChildren(of: tableNode)
        XCTAssertEqual(columns.count, 3, "表 \(table) 应当展开 3 列：\(columns.map(\.name))")

        // ⑤ 结果复制（产品渲染器；真剪贴板那一步由 ResultCopyProbeTests 证）
        let tsv = ResultClipboard.text(rows: last.rows, columns: last.columns, format: .tsv,
                                       tableName: table, schema: "public")
        let markdown = ResultClipboard.text(rows: last.rows, columns: last.columns, format: .markdown,
                                            tableName: table, schema: "public")

        // ⑥ 语法检查（`AppState.checkSyntax` —— 走同一条 ensureService 收口，缝指向真 service）
        let syntaxService = PostgresService(config: config, password: env.password)
        let (syntaxMessage, syntaxFailed) = await Self.runSyntaxCheck(
            config: config,
            service: syntaxService,
            sql: "select 1; select id from public.\(table)"
        )
        XCTAssertFalse(syntaxFailed, "语法检查判失败了：\(syntaxMessage)")
        await syntaxService.disconnect()

        return ChainReadout(
            serverVersion: info.version,
            testedLine: testedLine,
            statementCount: statements.count,
            insertedRows: last.rows.count,
            treeDepth: depth,
            tableColumns: columns.count,
            tsv: tsv,
            markdown: markdown,
            syntaxMessage: syntaxMessage
        )
    }

    /// 在真 `AppState` 上跑一次「语法检查」：`serviceOverride` 缝指向**真** service，
    /// 其余（切分 / 只放可 EXPLAIN 的语句 / 结论文案）全走生产代码。
    @MainActor
    private static func runSyntaxCheck(
        config: ConnectionConfig,
        service: any DatabaseService,
        sql: String
    ) async -> (message: String, failed: Bool) {
        let state = AppState()
        await state.startupChain?.value
        state.connections = [config]
        state.selectedConnectionID = config.id
        state.serviceOverride = service
        let tab = QueryTab(title: "acceptance", sql: sql,
                           connectionID: config.id, database: config.database)
        state.tabs = [tab]
        state.selectedTabID = tab.id
        await state.checkSyntax(for: tab.id)
        let checked = state.tabs.first { $0.id == tab.id }
        return (checked?.syntaxCheckMessage ?? "", checked?.syntaxCheckFailed ?? true)
    }

    // MARK: - REL-004：整条链

    func testRel004_fullChainOnRealPostgres() async throws {
        let env = try env()
        let readout = try await runChain(env: env)

        // ① 新建连接
        XCTAssertFalse(readout.serverVersion.isEmpty, "服务端版本读不到")
        XCTAssertTrue(readout.serverVersion.first.map { $0.isNumber } ?? false,
                      "服务端版本不是数字开头（驱动没报版本串）：\(readout.serverVersion)")
        // ② 测试连接：那一行结论是产品拼的（版本 / 库 / 用户三段都在）
        XCTAssertTrue(readout.testedLine.contains(env.database), "测试连接那句没带库名：\(readout.testedLine)")
        XCTAssertTrue(readout.testedLine.contains(env.user), "测试连接那句没带用户：\(readout.testedLine)")
        // ③ 多语句
        XCTAssertEqual(readout.statementCount, 3)
        XCTAssertEqual(readout.insertedRows, 2)
        // ④ 对象树四层
        XCTAssertEqual(readout.treeDepth, 4, "对象树只展开到第 \(readout.treeDepth) 层")
        XCTAssertEqual(readout.tableColumns, 3)
        // ⑤ 结果复制：表头在、中文没被转义坏、NULL 在 TSV 里留空、在 Markdown 里写 NULL
        XCTAssertTrue(readout.tsv.contains("id\tnote\tamount"), "TSV 表头不对：\(readout.tsv)")
        XCTAssertTrue(readout.tsv.contains("中文备注"), "TSV 丢了中文内容：\(readout.tsv)")
        XCTAssertTrue(readout.markdown.contains("NULL"), "Markdown 里空值没写成 NULL：\(readout.markdown)")
        // ⑥ 语法检查
        let expected = L(.stateCheckPassed, 2)
        XCTAssertTrue(readout.syntaxMessage.contains(expected),
                      "语法检查结论不是「\(expected)」：\(readout.syntaxMessage)")

        print("🧪 REL-004 真库整条链：\(readout.serverVersion) · 多语句 \(readout.statementCount) 条 "
              + "· 对象树 \(readout.treeDepth) 层 / \(readout.tableColumns) 列 · 复制 TSV \(readout.tsv.count) 字符 "
              + "· 语法检查「\(readout.syntaxMessage)」")
    }

    // MARK: - REL-005：四条错误路径可读

    func testRel005_errorPathsAreReadable() async throws {
        let env = try env()
        let language = LocalizationManager.shared.effectiveLanguage

        // ① 错误密码
        do {
            let service = PostgresService(config: configuration(env), password: env.password + "-wrong")
            _ = try await service.connect()
            XCTFail("错误密码竟然连上了")
            await service.disconnect()
        } catch {
            let described = try XCTUnwrap(
                ConnectionFailure.describe(error, target: .init(host: env.host, port: env.port,
                                                                database: env.database, username: env.user)),
                "错误密码这一档给不出可读说明：\(String(reflecting: error))"
            )
            XCTAssertFalse(described.summary.isEmpty)
            XCTAssertFalse(described.summary.hasPrefix("PSQLError("), "把驱动转储直接当人话：\(described.summary)")
            XCTAssertNotNil(described.suggestion, "错误密码没给排查建议")
            print("🧪 REL-005 错误密码 → \(described.fullText)")
        }

        // ② 错误端口（本机没有服务在听的那个端口）
        do {
            let service = PostgresService(config: configuration(env, port: 1), password: env.password)
            _ = try await service.connect()
            XCTFail("端口 1 竟然连上了")
            await service.disconnect()
        } catch {
            let described = try XCTUnwrap(ConnectionFailure.describe(error),
                                          "错误端口这一档给不出可读说明：\(String(reflecting: error))")
            XCTAssertFalse(described.summary.isEmpty)
            XCTAssertNotNil(described.suggestion, "错误端口没给排查建议")
            print("🧪 REL-005 错误端口 → \(described.summary)")
        }

        // ③ 不存在表 / ④ 不合法 SQL：同一条真连接上两条错误查询
        let service = PostgresService(config: configuration(env), password: env.password)
        _ = try await service.connect()
        defer { Task { await service.disconnect() } }

        let missingTable = "no_such_table_rel005"
        do {
            _ = try await run(service, "select * from public.\(missingTable)")
            XCTFail("不存在的表竟然查成功了")
        } catch {
            let message = ErrorPresenter.message(for: error)
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.contains("42P01"), "不存在表没带 SQLSTATE：\(message)")
            XCTAssertFalse(message.hasPrefix("PSQLError("), "把驱动转储直接当人话：\(message)")
            XCTAssertTrue(message.contains(missingTable), "文案没点名是哪张表：\(message)")
            // 查询类错误不许被连接失败那一档抢走（R-60）
            XCTAssertNil(ConnectionFailure.describe(error),
                         "42P01 被当成连接失败：\(ConnectionFailure.describe(error)?.summary ?? "")")
            print("🧪 REL-005 不存在表 → \(message.split(separator: "\n").first ?? "")")
        }

        do {
            _ = try await run(service, "selct 1 from")
            XCTFail("不合法 SQL 竟然执行成功了")
        } catch {
            let message = ErrorPresenter.message(for: error)
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.contains("42601"), "不合法 SQL 没带 SQLSTATE：\(message)")
            XCTAssertTrue(message.contains("selct"), "文案没点出错在哪：\(message)")
            print("🧪 REL-005 不合法 SQL → \(message.split(separator: "\n").first ?? "")")
        }
        XCTAssertEqual(language, LocalizationManager.shared.effectiveLanguage)
    }

    // MARK: - REL-006：崩溃零容忍

    /// 崩溃报告的落点。只判「这轮之后新出现的、名字里带本产品 / 本测试进程的」。
    private func crashReports(since: Date) -> [String] {
        let dir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        return files.compactMap { url -> String? in
            let name = url.lastPathComponent
            guard name.hasPrefix("Doyah") || name.contains("xctest") || name.contains("swift-test") else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, modified >= since else { return nil }
            return name
        }
    }

    func testRel006_fullFlowLeavesNoCrashLog() async throws {
        let env = try env()
        let started = Date().addingTimeInterval(-2)

        // 整条链跑三遍（连接 / 多语句 / 对象树 / 复制 / 语法检查 都在里面）
        for round in 1...3 {
            let readout = try await runChain(env: env)
            XCTAssertEqual(readout.treeDepth, 4, "第 \(round) 遍对象树没展开到底")
            XCTAssertTrue(readout.syntaxMessage.contains(L(.stateCheckPassed, 2)),
                          "第 \(round) 遍语法检查结论不对：\(readout.syntaxMessage)")
        }

        let reports = crashReports(since: started)
        XCTAssertTrue(reports.isEmpty, "本轮之后出现了崩溃报告：\(reports)")
        print("🧪 REL-006 三遍整链完成 · 新增崩溃报告 \(reports.count) 个")
    }

    // MARK: - REL-006（进程级）：产品 CLI 子进程不崩

    /// 进程级那一半：真跑 `DoyahCLI` 三条（正常多语句 / 对象树 / 错 SQL），
    /// 判「退出原因是 exit 而非 uncaughtSignal」+「没有新崩溃报告」。
    /// 二进制没构建时**跳过整条**（不是通过）——`swift test` 不负责构建 CLI 产品。
    func testRel006_cliSubprocessesDoNotCrash() throws {
        let env = try env()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TestsUISnapshot
            .deletingLastPathComponent()   // 仓库根
        let cli = root.appendingPathComponent(".build/debug/DoyahCLI")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw XCTSkip("\(cli.path) 没构建 ⇒ 进程级崩溃取证未做（先 swift build --product DoyahCLI）")
        }

        let started = Date().addingTimeInterval(-1)
        var childEnv = ProcessInfo.processInfo.environment
        childEnv["PGHOST"] = env.host
        childEnv["PGPORT"] = String(env.port)
        childEnv["PGUSER"] = env.user
        childEnv["PGDATABASE"] = env.database
        childEnv["PGPASSWORD"] = env.password
        childEnv["PGSSLMODE"] = "disable"

        func runCLI(_ arguments: [String]) -> (status: Int32, reason: Process.TerminationReason) {
            let process = Process()
            process.executableURL = cli
            process.arguments = arguments
            process.environment = childEnv
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch {
                XCTFail("CLI 起不来：\(error)")
                return (-1, .exit)
            }
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, process.terminationReason)
        }

        // ① 正常多语句（含中文与 NULL）
        let normal = runCLI(["-c", "select '中文' as note, null::text as empty; select 1"])
        XCTAssertEqual(normal.reason, .exit, "正常查询被信号打死")
        XCTAssertEqual(normal.status, 0, "正常查询退出码 \(normal.status)")

        // ② 对象树四层
        let tree = runCLI(["--tree", "--columns"])
        XCTAssertEqual(tree.reason, .exit, "对象树被信号打死")
        XCTAssertEqual(tree.status, 0, "对象树退出码 \(tree.status)")

        // ③ 错 SQL（应当以非 0 正常退出，而不是崩）
        let bad = runCLI(["-c", "selct 1 from"])
        XCTAssertEqual(bad.reason, .exit, "错 SQL 被信号打死")
        XCTAssertNotEqual(bad.status, 0, "错 SQL 竟然退出 0")

        let reports = crashReports(since: started)
        XCTAssertTrue(reports.isEmpty, "CLI 三条跑完出现崩溃报告：\(reports)")
        print("🧪 REL-006 CLI 子进程：正常 \(normal.status) · 树 \(tree.status) · 错 SQL \(bad.status) · 崩溃报告 \(reports.count)")
    }
}
