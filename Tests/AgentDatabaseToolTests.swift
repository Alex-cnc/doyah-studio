import XCTest
@testable import DoyahCore

/// `FR-AI-20` 第三片（`query_db`：只读直跑 / 写语句按次指纹入审批）—— 验收要点 ①⑤ 的机械判据。
final class AgentDatabaseToolTests: XCTestCase {

    /// 假执行器：记录被调到哪个入口、收到什么 SQL（**不真连库**）。
    private final class RecordingExecutor: AgentQueryExecutor, @unchecked Sendable {
        private(set) var readOnlyCalls: [String] = []
        private(set) var writeCalls: [String] = []
        var readOnlyResult = AgentQueryExecution(columns: ["id", "name"], affectedRows: 3, statementKind: "readQuery")
        var writeResult = AgentQueryExecution(affectedRows: 1, statementKind: "writeData")

        func executeReadOnly(sql: String) -> AgentQueryExecution {
            readOnlyCalls.append(sql)
            return readOnlyResult
        }

        func executeWrite(sql: String) -> AgentQueryExecution {
            writeCalls.append(sql)
            return writeResult
        }
    }

    private var executor: RecordingExecutor!
    /// 写操作逐次批准（`FR-AI-09` 口径）—— **注意 `AgentGuardPolicy()` 的默认是只读模式**。
    private var tool: AgentDatabaseTool!

    override func setUpWithError() throws {
        executor = RecordingExecutor()
        tool = AgentDatabaseTool(policy: AgentGuardPolicy(readOnly: false,
                                                          requireApprovalForHighRisk: true,
                                                          requireApprovalForWrites: true),
                                 executor: executor)
    }

    // MARK: - ① 只读语句**不经审批**直接返回

    func testReadOnlyStatementRunsWithoutApproval() {
        guard case .runReadOnly(let kind) = tool.plan(sql: "SELECT id, name FROM users") else {
            return XCTFail("只读语句应当可直接跑")
        }
        XCTAssertEqual(kind, .readQuery)

        guard case .rows(let output) = tool.run(sql: "SELECT id, name FROM users") else {
            return XCTFail("应当返回行摘要")
        }
        XCTAssertEqual(executor.readOnlyCalls.count, 1, "只读入口被调用一次")
        XCTAssertTrue(executor.writeCalls.isEmpty, "**不该走写入口**")
        XCTAssertEqual(output.columns, ["id", "name"])
        XCTAssertEqual(output.rowCount, 3)
        XCTAssertEqual(output.statementKind, "readQuery")
    }

    // MARK: - ⑤ 写语句按次指纹入审批；未批准不执行

    func testWriteStatementNeedsApprovalAndDoesNotRunBeforeThat() {
        let sql = "INSERT INTO users (name) VALUES ('x')"
        guard case .needsApproval(let request) = tool.plan(sql: sql) else {
            return XCTFail("写语句要审批")
        }
        XCTAssertFalse(request.fingerprint.isEmpty)
        XCTAssertTrue(request.payload.hasPrefix(sql), "审批单要带 SQL 原文：\(request.payload)")

        // 未批准 ⇒ 一次都不执行
        if case .refused(let code, _) = tool.run(sql: sql) {
            XCTAssertEqual(code, .approvalRequired)
        } else { XCTFail("未批准不许执行") }
        XCTAssertTrue(executor.writeCalls.isEmpty, "**未批准的写语句一次都不许执行**")
        XCTAssertTrue(executor.readOnlyCalls.isEmpty, "也不许悄悄走只读入口")

        // 指纹不符 / 没在已批准集合里 ⇒ 仍然不执行
        _ = tool.run(sql: sql, fingerprint: "deadbeef", granted: ["deadbeef"])
        _ = tool.run(sql: sql, fingerprint: request.fingerprint, granted: [])
        XCTAssertTrue(executor.writeCalls.isEmpty)

        // 批准且指纹一致 ⇒ 执行（走**写入口**）
        guard case .rows(let output) = tool.run(sql: sql, fingerprint: request.fingerprint,
                                                granted: [request.fingerprint]) else {
            return XCTFail("批准后应当执行")
        }
        XCTAssertEqual(executor.writeCalls, [sql])
        XCTAssertEqual(output.rowCount, 1, "影响行数如实带出")
    }

    /// **换 SQL ⇒ 指纹变 ⇒ 旧批准不算数**（不许一次批准变成这张表的总开关）。
    func testApprovalIsPerStatementNotPerTool() {
        guard case .needsApproval(let approved) = tool.plan(sql: "UPDATE users SET name = 'a' WHERE id = 1") else {
            return XCTFail("写语句要审批")
        }
        let other = "UPDATE users SET name = 'b' WHERE id = 2"
        guard case .refused(let code, _) = tool.run(sql: other, fingerprint: approved.fingerprint,
                                                    granted: [approved.fingerprint]) else {
            return XCTFail("换 SQL 之后旧批准不许生效")
        }
        XCTAssertEqual(code, .approvalRequired)
        XCTAssertTrue(executor.writeCalls.isEmpty)
    }

    // MARK: - 只读模式下连审批单都建不出来（沿用既有护栏口径）

    func testReadOnlyModeRefusesWritesInsteadOfAskingForApproval() {
        let readOnly = AgentDatabaseTool(policy: .readOnlyDefault, executor: executor)
        guard case .refused(let code, let detail) = readOnly.plan(sql: "DELETE FROM users") else {
            return XCTFail("只读模式下写语句要**直接拒**，不是排队等批")
        }
        XCTAssertEqual(code, .deniedByPolicy)
        XCTAssertEqual(detail, "dataChange", "细节串用语句类别的机器码，不写人话")

        // 只读语句在只读模式下照常直接跑
        guard case .runReadOnly = readOnly.plan(sql: "SELECT 1") else { return XCTFail("只读语句不受影响") }
        // 空 SQL 如实拒
        if case .refused(let emptyCode, _) = readOnly.plan(sql: "   ") {
            XCTAssertEqual(emptyCode, .emptyQuery)
        } else { XCTFail("空 SQL 要拒") }
    }

    // MARK: - 结构面：结果里没有行数据的落点

    func testRowsOutputHasNoPlaceForRowData() {
        let labels = Set(Mirror(reflecting: AgentToolRowsOutput(columns: [], rowCount: 0, statementKind: "x"))
            .children.compactMap { $0.label })
        XCTAssertEqual(labels, ["columns", "rowCount", "statementKind", "errorMessage"])
        for forbidden in ["rows", "data", "values", "content"] {
            XCTAssertFalse(labels.contains(forbidden), "行摘要里不许有 `\(forbidden)` 这种字段")
        }
    }

    func testExecutorErrorIsReportedNotSwallowed() {
        executor.readOnlyResult = AgentQueryExecution(columns: [], affectedRows: 0,
                                                     statementKind: "readQuery",
                                                     errorMessage: "relation \"ghost\" does not exist")
        guard case .rows(let output) = tool.run(sql: "SELECT * FROM ghost") else {
            return XCTFail("应当返回行摘要（失败也在摘要里如实说）")
        }
        XCTAssertEqual(output.errorMessage, "relation \"ghost\" does not exist")
    }
}
