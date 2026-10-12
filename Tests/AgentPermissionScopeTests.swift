import XCTest
@testable import DoyahCore

/// `FR-AI-12` 客户端半：**智能体不得超越当前连接权限**（队列 `L-125`，`Q46` 拍板「加」）。
///
/// 判据面 = 越权请求在**发起前**就被客户端拦下并如实报错：
/// ① 只读连接（`FR-CONN-17`）上的写 / 结构变更 / 权限变更；
/// ② 本机探到「不能建库」（`FR-META-11`）时的库级结构变更。
/// 两侧都成对判：**该拦的拦得住**（正例）+ **不该拦的不误拦**（对照），
/// 因为这一层是防御性冗余 —— 假阴性（拦错）比漏拦更难查。
final class AgentPermissionScopeTests: XCTestCase {

    // MARK: - 夹具

    private let policy = AgentGuardPolicy(
        readOnly: false,
        requireApprovalForHighRisk: true,
        requireApprovalForWrites: true
    )

    private let context = AgentActionRecord.Context(
        connectionName: "DemoPG", database: "appdb", model: "qwen2.5:7b"
    )

    private func assessment(_ sql: String) -> AgentGuardAssessment {
        AgentGuardrail.evaluate(sql: sql, databaseType: .postgresql, policy: policy)
    }

    private func finding(_ sql: String, _ permissions: AgentConnectionPermissions) -> AgentPermissionFinding? {
        AgentPermissionScope.blockingFinding(assessment: assessment(sql), permissions: permissions)
    }

    private let readOnlyConnection = AgentConnectionPermissions(isReadOnly: true)

    // MARK: - ① 只读连接：写 / 结构变更 / 权限变更一律拦

    func testReadOnlyConnectionBlocksDataChange() {
        let result = finding("UPDATE orders SET total = 0 WHERE id = 1", readOnlyConnection)
        guard case .readOnlyConnection(let statements)? = result else {
            return XCTFail("只读连接上的 UPDATE 没被拦下：\(String(describing: result))")
        }
        XCTAssertEqual(statements, ["UPDATE orders SET total = 0 WHERE id = 1"])
        XCTAssertNil(result?.capability, "只读连接不是「能力」问题，不该报成缺能力")
    }

    func testReadOnlyConnectionBlocksSchemaChange() {
        XCTAssertNotNil(finding("CREATE TABLE t (id int)", readOnlyConnection))
        XCTAssertNotNil(finding("DROP TABLE t", readOnlyConnection))
        XCTAssertNotNil(finding("TRUNCATE t", readOnlyConnection))
    }

    func testReadOnlyConnectionBlocksPrivilegeChange() {
        XCTAssertNotNil(finding("GRANT SELECT ON t TO u", readOnlyConnection))
    }

    /// 对照：只读连接上**不改库里东西**的语句放行 —— 与 `ExecutionSafety` 的
    /// `changesDataOrSchema` 同一条口径（`SET` 这类会话控制不算写入）。
    func testReadOnlyConnectionAllowsReadQueryAndSessionControl() {
        XCTAssertNil(finding("SELECT * FROM orders", readOnlyConnection))
        XCTAssertNil(finding("SET search_path TO public", readOnlyConnection))
    }

    /// 阴性对照：非只读连接上同一句 UPDATE 不该被这一层拦（拦它是护栏与审批的事）。
    func testWritableConnectionDoesNotBlockWrites() {
        XCTAssertNil(finding("UPDATE orders SET total = 0 WHERE id = 1", AgentConnectionPermissions()))
    }

    /// 整段提交里只要有一条越权，整段就拦；报出来的越权语句点名到那一条。
    func testReadOnlyConnectionBlocksWhenAnyStatementExceeds() {
        let result = finding("SELECT 1;\nDELETE FROM orders", readOnlyConnection)
        guard case .readOnlyConnection(let statements)? = result else {
            return XCTFail("多语句里夹了一条越权语句却没拦：\(String(describing: result))")
        }
        XCTAssertEqual(statements.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, ["DELETE FROM orders"])
    }

    // MARK: - ② 建库权限：本机探到「不可以」时拦库级结构变更

    func testMissingCreateDatabaseBlocksDatabaseLevelStatements() {
        let noCreate = AgentConnectionPermissions(canCreateDatabase: false)
        for sql in ["CREATE DATABASE app2", "DROP DATABASE app2", "ALTER DATABASE app2 RENAME TO app3"] {
            let result = finding(sql, noCreate)
            XCTAssertEqual(result?.capability, .createDatabase, "这句没被建库权限拦住：\(sql)")
            XCTAssertEqual(result?.statements, [sql])
        }
    }

    /// 对照：能力对得上才拦 —— 「不能建库」不该拦建表，哪怕表名 / 列名叫 `database`。
    func testMissingCreateDatabaseDoesNotBlockTableLevelStatements() {
        let noCreate = AgentConnectionPermissions(canCreateDatabase: false)
        XCTAssertNil(finding("CREATE TABLE t (database text)", noCreate))
        XCTAssertNil(finding("INSERT INTO t (database) VALUES ('x')", noCreate))
        XCTAssertNil(finding("SELECT * FROM database", noCreate))
    }

    func testCreateDatabaseAllowedWhenProbeSaysYes() {
        let yesCreate = AgentConnectionPermissions(canCreateDatabase: true)
        XCTAssertNil(finding("CREATE DATABASE app2", yesCreate))
    }

    /// 未知不拦：`nil` 是「本机没探到 / 方言不支持」，这一层不许据此拦人（不制造假阴性）。
    func testUnknownCreateDatabaseDoesNotBlock() {
        XCTAssertNil(finding("CREATE DATABASE app2", AgentConnectionPermissions(canCreateDatabase: nil)))
    }

    /// 形状判据：缺省值 = 什么都不知道 = 什么都不拦（既有调用点行为一字不变）。
    func testUnknownPermissionsNeverBlock() {
        let sqls = [
            "SELECT 1",
            "UPDATE t SET x = 1 WHERE id = 1",
            "DROP TABLE t",
            "CREATE DATABASE app2",
            "GRANT SELECT ON t TO u"
        ]
        for sql in sqls {
            XCTAssertNil(finding(sql, .unknown), "缺省权限事实不该拦任何语句：\(sql)")
        }
    }

    // MARK: - 关键字取词（库级判定只吃语句开头那一段）

    func testLeadingKeywordsSkipLeadingCommentsAndWhitespace() {
        XCTAssertEqual(
            AgentPermissionScope.leadingKeywords(
                in: "  -- 建库\n /* note */ CREATE   DATABASE app2",
                limit: 2
            ),
            ["CREATE", "DATABASE"]
        )
        XCTAssertEqual(
            AgentPermissionScope.leadingKeywords(in: "drop\tdatabase app2", limit: 2),
            ["DROP", "DATABASE"]
        )
        XCTAssertEqual(
            AgentPermissionScope.leadingKeywords(in: "CREATE DATABASE app2", limit: 3),
            ["CREATE", "DATABASE", "APP2"]
        )
    }

    func testLeadingKeywordsStopAtNonKeywordCharacters() {
        XCTAssertEqual(AgentPermissionScope.leadingKeywords(in: "SELECT * FROM t"), ["SELECT"])
        XCTAssertEqual(AgentPermissionScope.leadingKeywords(in: "'x' || 'y'"), [])
        XCTAssertEqual(AgentPermissionScope.leadingKeywords(in: ""), [])
    }

    /// 库级判定只对被护栏判成**结构变更**的语句生效（数据变更里的 `database` 不算）。
    func testRequiresDatabaseCreationOnlyForSchemaChangeStatements() {
        let create = assessment("CREATE DATABASE app2").statements.first
        let insert = assessment("INSERT INTO t (database) VALUES ('x')").statements.first
        XCTAssertEqual(create?.kind, .schemaChange)
        XCTAssertEqual(insert?.kind, .dataChange)
        XCTAssertTrue(AgentPermissionScope.requiresDatabaseCreation(try XCTUnwrap(create)))
        XCTAssertFalse(AgentPermissionScope.requiresDatabaseCreation(try XCTUnwrap(insert)))
    }

    // MARK: - 如实报错（语言由调用方给）

    func testMessagesNameTheOffendingStatementInBothLanguages() {
        let sql = "UPDATE orders SET total = 0 WHERE id = 1"
        guard let finding = finding(sql, readOnlyConnection) else {
            return XCTFail("只读连接上的写语句没被拦下")
        }

        let zh = AgentPermissionScope.message(for: finding, language: .simplifiedChinese)
        let en = AgentPermissionScope.message(for: finding, language: .english)

        XCTAssertTrue(zh.contains(sql), "中文那句要点名越权语句原文")
        XCTAssertTrue(en.contains(sql), "英文那句要点名越权语句原文")
        XCTAssertTrue(zh.contains("只读"), "中文那句要说清是只读连接")
        XCTAssertTrue(en.contains("read-only"), "英文那句要说清是只读连接")
        XCTAssertNotEqual(zh, en)
    }

    func testCapabilityMessagesAreLocalized() {
        let noCreate = AgentConnectionPermissions(canCreateDatabase: false)
        guard let finding = finding("CREATE DATABASE app2", noCreate) else {
            return XCTFail("探到「不能建库」时库级语句没被拦下")
        }

        let zh = AgentPermissionScope.message(for: finding, language: .simplifiedChinese)
        let en = AgentPermissionScope.message(for: finding, language: .english)
        XCTAssertTrue(zh.contains("CREATE DATABASE app2"))
        XCTAssertTrue(zh.contains(AgentPermissionScope.capabilityName(.createDatabase, language: .simplifiedChinese)))
        XCTAssertNotEqual(
            AgentPermissionScope.capabilityName(.createDatabase, language: .simplifiedChinese),
            AgentPermissionScope.capabilityName(.createDatabase, language: .english)
        )
        XCTAssertNotEqual(zh, en)
    }

    // MARK: - 闸门接线：发起前拦下 = 连审批单都没有

    func testGateDeniesWriteOnReadOnlyConnectionWithoutApproval() {
        let sql = "UPDATE orders SET total = 0 WHERE id = 1"
        let submission = AgentActionGate.submit(
            sql: sql,
            databaseType: .postgresql,
            policy: policy,
            context: context,
            permissions: readOnlyConnection,
            language: .simplifiedChinese
        )

        guard case .denied(let record) = submission else {
            return XCTFail("只读连接上的写语句没被闸门拒：\(submission)")
        }
        XCTAssertFalse(submission.awaitsApproval, "发起前就拦下的请求不该有审批单")
        XCTAssertEqual(record.outcome, .denied)
        XCTAssertEqual(record.detail, AgentPermissionScope.message(
            for: .readOnlyConnection(statements: [sql]),
            language: .simplifiedChinese
        ))
    }

    func testGateDeniesDatabaseCreationWhenProbeSaysNo() {
        let sql = "CREATE DATABASE app2"
        let submission = AgentActionGate.submit(
            sql: sql,
            databaseType: .postgresql,
            policy: policy,
            context: context,
            permissions: AgentConnectionPermissions(canCreateDatabase: false),
            language: .simplifiedChinese
        )

        guard case .denied(let record) = submission else {
            return XCTFail("探到「不能建库」时库级语句没被闸门拒：\(submission)")
        }
        XCTAssertEqual(record.outcome, .denied)
        XCTAssertTrue((record.detail ?? "").contains(sql))
    }

    /// 对照：同一句 SQL 在**没有越权**的连接上照旧走原路（该审批就审批）。
    func testGateKeepsApprovalPathOnHealthyConnection() {
        let sql = "UPDATE orders SET total = 0 WHERE id = 1"
        let submission = AgentActionGate.submit(
            sql: sql,
            databaseType: .postgresql,
            policy: policy,
            context: context,
            permissions: AgentConnectionPermissions(isReadOnly: false, canCreateDatabase: true),
            language: .simplifiedChinese
        )
        XCTAssertTrue(submission.awaitsApproval, "没有越权就不该在这一层被拦：\(submission)")
    }

    /// 形状判据：不传权限事实（缺省 `.unknown`）时行为与改动前一致。
    func testGateDefaultsBehaveAsBefore() {
        let sql = "UPDATE orders SET total = 0 WHERE id = 1"
        let submission = AgentActionGate.submit(
            sql: sql,
            databaseType: .postgresql,
            policy: policy,
            context: context,
            language: .simplifiedChinese
        )
        XCTAssertTrue(submission.awaitsApproval)
    }

    // MARK: - 源码接线锚点：界面这条路真的把连接事实喂给了闸门

    func testAppStateFeedsConnectionFactsIntoTheGate() {
        let source = try! String(contentsOf: appStateURL, encoding: .utf8)
        XCTAssertTrue(
            source.contains("permissions: AgentConnectionPermissions("),
            "AppState 没把连接权限事实传进闸门 ⇒ 这一层永远不会生效"
        )
        XCTAssertTrue(source.contains("isReadOnly: selectedConnection?.isReadOnly ?? false"))
        XCTAssertTrue(source.contains("canCreateDatabase: canCreateDatabase"), "建库那一项没接上 FR-META-11 的探测结果")
    }

    private var appStateURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/AppState.swift")
    }
}
