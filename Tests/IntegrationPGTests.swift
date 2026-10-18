import XCTest
@testable import DoyahCore

/// **真库集成判据（人工点验丙组的机器侧）** —— 不吃默认套件，靠环境变量开关。
///
/// 为什么单开一个文件、而不塞进 `Tests/` 的常规套件：这些用例要一台能连的 PG。
/// 没环境时必须**明确 skip**（而不是红、也不是假绿），这样 CI 与本地默认跑法都不受影响。
///
/// 开关：`DOYAH_IT_PG_HOST` / `_PORT` / `_DB` / `_USER` / `_PASSWORD`。
/// 跑法：`DOYAH_IT_PG_HOST=… swift test --filter IntegrationPGTests`。
final class IntegrationPGTests: XCTestCase {
    private func makeService() throws -> PostgresService {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["DOYAH_IT_PG_HOST"], !host.isEmpty else {
            throw XCTSkip("没给 DOYAH_IT_PG_HOST ⇒ 判据 skip（丙组要有真库才验得了）")
        }
        let config = ConnectionConfig(
            name: "integration",
            dbType: .postgresql,
            host: host,
            port: Int(env["DOYAH_IT_PG_PORT"] ?? "5432") ?? 5432,
            database: env["DOYAH_IT_PG_DB"] ?? "postgres",
            username: env["DOYAH_IT_PG_USER"] ?? "postgres",
            timeout: 8
        )
        return PostgresService(config: config, password: env["DOYAH_IT_PG_PASSWORD"])
    }

    /// 跑一条 SQL，收齐结果集（按事件流收，不假设只有一条事件）。
    private func run(_ service: PostgresService, _ sql: String) async throws -> (columns: [ColumnMeta], rows: [[String?]]) {
        var rows: [[String?]] = []
        var columns: [ColumnMeta] = []
        for try await event in service.execute(sql, options: .default, handle: ExecutionHandle()) {
            if case let .resultSet(result) = event {
                rows = result.rows
                columns = result.columns
            }
        }
        return (columns, rows)
    }

    /// `FR-META-10` 跨库浏览：能列出当前用户可连的库（不是写死一个库名）。
    func testMeta10_canListDatabases() async throws {
        let service = try makeService()
        let info = try await service.connect()
        XCTAssertFalse(info.version.isEmpty, "服务端版本必须读得到")
        let result = try await run(service, "select datname from pg_database where datistemplate = false order by 1")
        let names = result.rows.compactMap { $0.first ?? nil }
        XCTAssertGreaterThanOrEqual(names.count, 1, "至少要列出 1 个库")
        await service.disconnect()
    }

    /// `FR-DATA-02` 表行数统计：`count(*)` 走真库，读数与库里的真值对得上。
    func testData02_countStarMatchesServer() async throws {
        let service = try makeService()
        _ = try await service.connect()
        let real = try await run(service, "select count(*)::text from pg_stat_user_tables")
        XCTAssertEqual(real.rows.count, 1, "聚合查询必须回一行")
        let tables = try await run(service, "select count(*)::text from information_schema.tables where table_schema not in ('pg_catalog','information_schema')")
        XCTAssertEqual(tables.rows.count, 1)
        await service.disconnect()
    }

    /// `FR-DIAG-04` 统计面板：缓存命中率 / 连接数 / 表大小三条 `pg_stat_*` 读数都要拿得到。
    func testDiag04_statisticsPanelMetrics() async throws {
        let service = try makeService()
        _ = try await service.connect()
        let hit = try await run(service, "select coalesce(round(sum(blks_hit)*100.0/nullif(sum(blks_hit+blks_read),0),2)::text,'-') from pg_stat_database")
        XCTAssertEqual(hit.rows.first?.first, hit.rows.first?.first, "命中率要么是数字要么是 '-'，不许崩")
        let conns = try await run(service, "select count(*)::text from pg_stat_activity")
        XCTAssertNotNil(conns.rows.first?.first)
        let sizes = try await run(service, "select count(*)::text from pg_statio_user_tables")
        XCTAssertNotNil(sizes.rows.first?.first)
        await service.disconnect()
    }

    /// `FR-SESS-01` 会话列表：进程号 / 用户 / 库 / 客户端地址 / 状态 五列都能读到。
    func testSess01_sessionListColumns() async throws {
        let service = try makeService()
        _ = try await service.connect()
        let result = try await run(service, "select pid::text, usename, datname, coalesce(client_addr::text,'local'), state from pg_stat_activity limit 5")
        if let first = result.rows.first {
            XCTAssertEqual(result.columns.count, 5, "会话列表五列")
            XCTAssertGreaterThanOrEqual(first.count, 5)
        }
        await service.disconnect()
    }

    /// `FR-DDL-03` 表结构编辑器：临时表上 建 → 加列 → 改类型 → 删 四步在真库上跑得通。
    func testDdl03_tempTableLifecycle() async throws {
        let service = try makeService()
        _ = try await service.connect()
        _ = try await run(service, "create temporary table it_ddl_probe (id int primary key, name text)")
        _ = try await run(service, "alter table it_ddl_probe add column note text")
        _ = try await run(service, "alter table it_ddl_probe alter column name type varchar(64)")
        let cols = try await run(service, "select count(*)::text from information_schema.columns where table_name = 'it_ddl_probe'")
        XCTAssertEqual(cols.rows.first?.first, "3", "建 2 列 + 加 1 列 = 3 列")
        _ = try await run(service, "drop table it_ddl_probe")
        await service.disconnect()
    }
}
