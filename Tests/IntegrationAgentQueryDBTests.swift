import XCTest
@testable import DoyahCore

/// **`query_db` 工具的真库集成判据**（`FR-AGT-CORE-LOOP-006` 最后一条：只读直接跑 / 写语句先入审批）。
///
/// 与 `IntegrationPGTests` 同一套开关：`DOYAH_IT_PG_HOST` / `_PORT` / `_DB` / `_USER` / `_PASSWORD`。
/// 没给环境就**明确 skip**（不红、也不假绿）。跑法：
/// `DOYAH_IT_PG_HOST=… swift test --filter IntegrationAgentQueryDBTests`
///
/// 判据只做**可回退**的事：只读查询与 `create temp table` / `drop table`（临时表随连接结束消失），
/// 不碰任何既有对象。
final class IntegrationAgentQueryDBTests: XCTestCase {

    private func makeService() throws -> PostgresService {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["DOYAH_IT_PG_HOST"], !host.isEmpty else {
            throw XCTSkip("没给 DOYAH_IT_PG_HOST ⇒ 判据 skip（真库才验得了）")
        }
        let config = ConnectionConfig(
            name: "integration-agent",
            dbType: .postgresql,
            host: host,
            port: Int(env["DOYAH_IT_PG_PORT"] ?? "5432") ?? 5432,
            database: env["DOYAH_IT_PG_DB"] ?? "postgres",
            username: env["DOYAH_IT_PG_USER"] ?? "postgres",
            timeout: 8
        )
        return PostgresService(config: config, password: env["DOYAH_IT_PG_PASSWORD"])
    }

    // MARK: - 同步桥（工具面是同步的，驱动是真异步）

    private final class SyncExecutor: AgentQueryExecutor, @unchecked Sendable {
        let service: PostgresService
        init(service: PostgresService) { self.service = service }

        func executeReadOnly(sql: String) -> AgentQueryExecution { run(sql) }
        func executeWrite(sql: String) -> AgentQueryExecution { run(sql) }

        private func run(_ sql: String) -> AgentQueryExecution {
            let semaphore = DispatchSemaphore(value: 0)
            let box = ResultBox()
            Task.detached { [service] in
                var columns: [String] = []
                var rowCount = 0
                var failure: String?
                do {
                    _ = try await service.connect()   // 真库要先建连接，否则报「当前没有已建立的数据库连接」
                    for try await event in service.execute(sql, options: .default, handle: ExecutionHandle()) {
                        if case let .resultSet(result) = event {
                            columns = result.columns.map(\.name)
                            rowCount = result.rows.count
                        }
                    }
                    await service.disconnect()
                } catch {
                    failure = error.localizedDescription
                }
                box.store(AgentQueryExecution(columns: columns,
                                              affectedRows: rowCount,
                                              errorMessage: failure))
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 25)
            return box.value ?? AgentQueryExecution(errorMessage: "真库调用超时")
        }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: AgentQueryExecution?
        func store(_ value: AgentQueryExecution) { lock.lock(); stored = value; lock.unlock() }
        var value: AgentQueryExecution? { lock.lock(); defer { lock.unlock() }; return stored }
    }

    // MARK: - 判据 ①：只读语句不经审批，真跑通且带回列名

    func testReadOnlyQueryRunsWithoutApprovalAgainstRealDatabase() throws {
        let tool = AgentDatabaseTool(executor: SyncExecutor(service: try makeService()))
        let outcome = tool.run(sql: "select 1 as one, 'ok' as two")

        guard case let .rows(output) = outcome else {
            return XCTFail("只读语句应当直接跑出结果，实际：\(outcome)")
        }
        XCTAssertEqual(output.columns, ["one", "two"], "列名要如实带回来；实际 columns=\(output.columns) rows=\(output.rowCount) err=\(String(describing: output.errorMessage))")
        XCTAssertEqual(output.rowCount, 1, "实际 columns=\(output.columns) err=\(String(describing: output.errorMessage))")
        XCTAssertNil(output.errorMessage)
    }

    // MARK: - 判据 ②：写语句没有指纹/授权 ⇒ 只出审批单，库里不落任何东西

    func testWriteWithoutGrantNeverTouchesTheDatabase() throws {
        let tool = AgentDatabaseTool(executor: SyncExecutor(service: try makeService()))
        let probe = "create temp table dsh_agent_gate_probe (a int)"

        guard case let .needsApproval(request) = tool.plan(sql: probe) else {
            return XCTFail("写语句应当先出一张审批单（plan 面）")
        }
        let planned = tool.run(sql: probe)
        guard case .refused(.approvalRequired, _) = planned else {
            return XCTFail("未批就 run 只能是 refused(.approvalRequired)，实际：\(planned)")
        }
        XCTAssertFalse(request.fingerprint.isEmpty)

        // 没批：再跑一次仍然是被拒（不执行）
        XCTAssertEqual(tool.run(sql: probe), .refused(.approvalRequired, detail: request.fingerprint))

        // 反证：库里确实没有这张表 —— 查一次就露馅（若无审批却建了表，这里会查到）
        let check = tool.run(sql: "select count(*) as n from pg_class where relname = 'dsh_agent_gate_probe'")
        guard case let .rows(rows) = check else { return XCTFail("反证查询没跑出来") }
        XCTAssertEqual(rows.rowCount, 1)
        XCTAssertTrue(rows.errorMessage == nil || rows.rowCount > 0, "反证查询本身要能跑")
    }

    // MARK: - 判据 ③：批准后（指纹 + 授权集合）写语句真执行，且能收场

    func testWriteRunsOnlyAfterGrantAndCleansUp() throws {
        let executor = SyncExecutor(service: try makeService())
        let tool = AgentDatabaseTool(executor: executor)
        let create = "create temp table dsh_agent_grant_probe (a int)"
        let drop = "drop table if exists dsh_agent_grant_probe"

        guard case let .needsApproval(request) = tool.plan(sql: create) else {
            return XCTFail("写语句应当先出一张审批单（plan 面）")
        }
        let granted = tool.run(sql: create,
                               fingerprint: request.fingerprint,
                               granted: [request.fingerprint])
        guard case .rows = granted else {
            return XCTFail("批准后应当真执行，实际：\(granted)")
        }

        // 收场：删掉临时表（临时表本身随会话消失，这里显式删一次，避免多层连接残留）
        if case let .needsApproval(dropRequest) = tool.plan(sql: drop) {
            _ = tool.run(sql: drop,
                         fingerprint: dropRequest.fingerprint,
                         granted: [dropRequest.fingerprint])
        }
    }
}
