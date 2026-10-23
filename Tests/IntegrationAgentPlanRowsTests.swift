import XCTest
@testable import DoyahCore

/// A4 的**真库**判据（§9.1.16：审批单上的「预计影响行数」）。
///
/// 为什么必须连真库：`Plan Rows` 是优化器的估算，只有真 PostgreSQL 才产出它 ——
/// 本地造一个字符串样本只能证明「解析器会读」，证明不了「这条路上真能取到数」。
///
/// 跑法（口令只进环境变量，不回显）：
/// ```bash
/// DOYAH_IT_PG_HOST=192.168.5.217 DOYAH_IT_PG_PORT=5432 DOYAH_IT_PG_DATABASE=zxvmax \
/// DOYAH_IT_PG_USER=zxvmax DOYAH_IT_PG_PASSWORD="$(cat <scratch>/pg217.pw)" \
///   swift test --filter IntegrationAgentPlanRowsTests
/// ```
/// 没有环境变量 ⇒ **按设计跳过**（skip 既不是红、也不是假绿）。
///
/// **它只读不写**：`EXPLAIN`（不带 `ANALYZE`）不会执行目标语句；用例自己也不发任何 DML。
final class IntegrationAgentPlanRowsTests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    func testExplainPlanRowsAgainstRealPostgres() async throws {
        guard let host = env["DOYAH_IT_PG_HOST"],
              let user = env["DOYAH_IT_PG_USER"],
              let database = env["DOYAH_IT_PG_DATABASE"],
              let password = env["DOYAH_IT_PG_PASSWORD"] else {
            throw XCTSkip("缺 DOYAH_IT_PG_* 环境变量 —— 按环境跳过，不算通过")
        }

        let config = ConnectionConfig(name: "it-plan-rows",
                                      dbType: .postgresql,
                                      host: host,
                                      port: Int(env["DOYAH_IT_PG_PORT"] ?? "5432"),
                                      database: database,
                                      username: user,
                                      timeout: 8)
        let service = PostgresService(config: config, password: password)
        _ = try await service.connect()
        defer { Task { await service.disconnect() } }

        // ① 去靶库自己问「有哪张表、有哪一列」—— 不写死表名/列名（换实例也能跑）。
        let relation = try await firstColumn(service, sql: """
            SELECT table_name FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            ORDER BY table_name LIMIT 1
            """)
        let table = try XCTUnwrap(relation, "public 下没有基表 —— 这个实例不适合当靶子")
        let column = try await firstColumn(service, sql: """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = '\(table)'
            ORDER BY ordinal_position LIMIT 1
            """)
        let columnName = try XCTUnwrap(column, "表 \(table) 没有列")
        let total = try await firstColumn(service, sql: "SELECT count(*)::text FROM \"\(table)\"")
            .flatMap(Int.init)

        // ② 产品口径走一遍：拼 EXPLAIN → 用产品自己的驱动执行 → 用产品自己的解析器读
        let update = "UPDATE \"\(table)\" SET \"\(columnName)\" = \"\(columnName)\" WHERE \"\(columnName)\" IS NOT NULL"
        let statement = try XCTUnwrap(AgentPlanRows.explainStatement(for: update),
                                      "这条改进数据的语句应当能包成 EXPLAIN")
        XCTAssertFalse(statement.uppercased().contains("ANALYZE"), "带 ANALYZE 的 EXPLAIN 会真的改数据")

        let json = try await firstColumn(service, sql: statement)
        let estimate = AgentPlanRows.estimate(json: json)
        guard case .rows(let planRows) = estimate else {
            return XCTFail("真库上没估出来：\(estimate) —— 原始答复：\(json ?? "nil")")
        }
        print("🎯 A4 真库读数：表=\(table) 列=\(columnName) Plan Rows=\(planRows) 表行数=\(total.map(String.init) ?? "?")")

        XCTAssertGreaterThan(planRows, 0, "非空表上的 UPDATE 计划行数不该是 0")
        if let total, total > 0 {
            XCTAssertLessThanOrEqual(planRows, total * 4,
                                     "估算行数不该离谱地高于表规模（\(planRows) vs \(total)）")
        }

        // ③ 只读语句**不估**（不依赖库的产品判定：SELECT 没有「影响多少行」这回事）
        XCTAssertNil(AgentPlanRows.explainStatement(for: "SELECT * FROM \"\(table)\""))
    }

    /// 取一行一列（结果集只有一个值）。**不打印行数据**，只把标量交回调用方。
    private func firstColumn(_ service: PostgresService, sql: String) async throws -> String? {
        var value: String?
        for try await event in service.execute(sql, options: .default, handle: ExecutionHandle()) {
            if case .resultSet(let result) = event {
                value = result.rows.first?.first ?? nil
            }
        }
        return value
    }
}
